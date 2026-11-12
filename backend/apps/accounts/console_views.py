"""Staff actions on enrolment applications in the web console. Rules stay in the service."""

from django.conf import settings
from django.contrib import messages
from django.core.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils.cache import patch_cache_control
from django.views.decorators.http import require_POST

from apps.accounts.api.errors import MESSAGES
from apps.accounts.models import DeviceEnrolmentRequest
from apps.accounts.services import enrolment
from apps.providers import registry

REASON_REQUIRED = "Le motif est obligatoire."


def _change_url(req) -> str:
    return reverse("admin:accounts_deviceenrolmentrequest_change", args=[req.pk])


def _run(request, pk, action, success_message):
    req = get_object_or_404(DeviceEnrolmentRequest, pk=pk)
    try:
        action(req)
    except enrolment.EnrolmentError as exc:
        if exc.code == "forbidden":
            raise PermissionDenied from exc
        messages.error(request, MESSAGES.get(exc.code, exc.code))
    else:
        messages.success(request, success_message)
    return redirect(_change_url(req))


@require_POST
def approve(request, pk):
    return _run(request, pk, lambda req: enrolment.approve(req, staff=request.user), "Demande approuvée.")


def _with_reason(request, pk, service_function, success_message):
    reason = request.POST.get("reason", "").strip()
    if not reason:
        req = get_object_or_404(DeviceEnrolmentRequest, pk=pk)
        messages.error(request, REASON_REQUIRED)
        return redirect(_change_url(req))
    return _run(
        request, pk, lambda req: service_function(req, staff=request.user, reason=reason), success_message
    )


@require_POST
def refuse(request, pk):
    return _with_reason(request, pk, enrolment.refuse, "Demande refusée.")


@require_POST
def hold(request, pk):
    return _with_reason(request, pk, enrolment.hold, "Demande mise en attente.")


@require_POST
def send(request, pk):
    """Issue a fresh confirmation number and show the WhatsApp link once."""
    req = get_object_or_404(DeviceEnrolmentRequest, pk=pk)
    try:
        code = enrolment.issue_code(req, staff=request.user)
    except enrolment.EnrolmentError as exc:
        if exc.code == "forbidden":
            raise PermissionDenied from exc
        messages.error(request, MESSAGES.get(exc.code, exc.code))
        return redirect(_change_url(req))
    link = registry.get_messaging().whatsapp_link(req.phone, enrolment.CONFIRMATION_MESSAGE.format(code=code))
    response = render(
        request,
        "console/enrolment_send.html",
        {
            "req": req,
            "whatsapp_link": link,
            "official_number": settings.OFFICIAL_WHATSAPP_NUMBER or "non configuré",
            "back_url": _change_url(req),
            "title": "Envoyer le numéro de confirmation",
        },
    )
    # The page carries the confirmation number: it must never be cached.
    patch_cache_control(response, no_store=True)
    return response
