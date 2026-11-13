"""Staff decisions on payments in the web console. Rules stay in the payments service."""

from django.contrib import messages
from django.core.exceptions import PermissionDenied
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect
from django.urls import reverse
from django.utils.cache import patch_cache_control
from django.views.decorators.http import require_GET, require_POST

from apps.accounts.api.errors import MESSAGES

from .models import Payment
from .services import payments
from .services.errors import BookingError

DECIDED = "Ce paiement a déjà été traité."


def _back(payment):
    return redirect(reverse("admin:bookings_payment_change", args=[payment.pk]))


def _run(request, payment, action, success):
    try:
        action()
    except BookingError as exc:
        if exc.code == "forbidden":
            raise PermissionDenied from exc
        messages.error(request, DECIDED if exc.code == "invalid_state" else MESSAGES.get(exc.code, exc.code))
    else:
        messages.success(request, success)
    return _back(payment)


@require_POST
def confirm_payment(request, pk):
    payment = get_object_or_404(Payment, pk=pk)
    return _run(
        request,
        payment,
        lambda: payments.confirm_payment(
            payment,
            staff=request.user,
            amount_matches=request.POST.get("amount_matches") == "on",
            reference_matches=request.POST.get("reference_matches") == "on",
        ),
        "Paiement confirmé.",
    )


@require_POST
def refuse_payment(request, pk):
    payment = get_object_or_404(Payment, pk=pk)
    return _run(
        request,
        payment,
        lambda: payments.refuse_payment(payment, staff=request.user, reason=request.POST.get("reason", "")),
        "Paiement refusé.",
    )


@require_POST
def record_refund(request, pk):
    payment = get_object_or_404(Payment, pk=pk)
    return _run(
        request,
        payment,
        lambda: payments.record_refund(
            payment, staff=request.user, reference=request.POST.get("reference", "")
        ),
        "Remboursement enregistré.",
    )


@require_GET
def proof_image(request, pk):
    payment = get_object_or_404(Payment.objects.select_related("proof"), pk=pk)
    try:
        data = payments.read_proof(payment, staff=request.user)
    except BookingError as exc:
        raise PermissionDenied from exc
    response = HttpResponse(data, content_type="image/jpeg")
    # A payment receipt must never be kept by a browser or a proxy.
    patch_cache_control(response, no_store=True)
    return response
