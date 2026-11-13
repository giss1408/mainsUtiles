"""Staff decisions on verifications in the web console. Rules stay in the review service."""

from datetime import date

from django.conf import settings
from django.contrib import messages
from django.core.exceptions import PermissionDenied
from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils.cache import patch_cache_control
from django.views.decorators.http import require_GET, require_POST

from apps.accounts.api.errors import MESSAGES
from apps.providers import registry
from apps.verification.models import AddressProof, Guarantor, IdentityVerification, TrustedContact
from apps.verification.services import contacts, review
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError

INVALID_DATE = "Date invalide."
ALREADY_DECIDED = "Cette vérification a déjà été traitée."


def _back(record):
    name = f"admin:verification_{type(record)._meta.model_name}_change"
    return redirect(reverse(name, args=[record.pk]))


def _run(request, record, action, success_message):
    try:
        action()
    except VerificationError as exc:
        if exc.code == "forbidden":
            raise PermissionDenied from exc
        text = ALREADY_DECIDED if exc.code == "invalid_state" else MESSAGES.get(exc.code, exc.code)
        messages.error(request, text)
    except _InvalidDate:
        messages.error(request, INVALID_DATE)
    else:
        messages.success(request, success_message)
    return _back(record)


class _InvalidDate(Exception):
    pass


def _date(request, name: str) -> date:
    try:
        return date.fromisoformat(request.POST.get(name, "").strip())
    except ValueError as exc:
        raise _InvalidDate from exc


@require_POST
def confirm_identity(request, pk):
    record = get_object_or_404(IdentityVerification, pk=pk)
    return _run(
        request,
        record,
        lambda: review.confirm_identity(
            record,
            staff=request.user,
            full_name=request.POST.get("full_name", ""),
            date_of_birth=_date(request, "date_of_birth"),
            document_number=request.POST.get("document_number", ""),
            document_expires_on=_date(request, "document_expires_on"),
        ),
        "Identité confirmée.",
    )


@require_POST
def refuse_identity(request, pk):
    record = get_object_or_404(IdentityVerification, pk=pk)
    return _run(
        request,
        record,
        lambda: review.refuse_identity(record, staff=request.user, reason=request.POST.get("reason", "")),
        "Identité refusée.",
    )


@require_POST
def confirm_address(request, pk):
    record = get_object_or_404(AddressProof, pk=pk)
    return _run(
        request,
        record,
        lambda: review.confirm_address(
            record,
            staff=request.user,
            holder_name=request.POST.get("holder_name", ""),
            reference_number=request.POST.get("reference_number", ""),
            issued_on=_date(request, "issued_on"),
            name_matches=request.POST.get("name_matches") == "on",
            address_consistent=request.POST.get("address_consistent") == "on",
            location_id=request.POST.get("location_id", ""),
        ),
        "Justificatif confirmé.",
    )


@require_POST
def refuse_address(request, pk):
    record = get_object_or_404(AddressProof, pk=pk)
    return _run(
        request,
        record,
        lambda: review.refuse_address(
            record,
            staff=request.user,
            reason=request.POST.get("reason", ""),
            refuse_location=request.POST.get("refuse_location") == "on",
        ),
        "Justificatif refusé.",
    )


def _photo_response(request, photo) -> HttpResponse:
    try:
        data = review.read_photo(photo, staff=request.user)
    except VerificationError as exc:
        raise PermissionDenied from exc
    response = HttpResponse(data, content_type="image/jpeg")
    # Identity photos must never be kept by a browser or a proxy.
    response["Cache-Control"] = "no-store"
    return response


@require_GET
def identity_photo(request, pk, photo_id):
    record = get_object_or_404(IdentityVerification.objects.select_related("front", "back", "selfie"), pk=pk)
    for photo in (record.front, record.back, record.selfie):
        if photo.pk == photo_id:
            return _photo_response(request, photo)
    raise Http404


@require_GET
def address_photo(request, pk, photo_id):
    record = get_object_or_404(AddressProof.objects.select_related("photo"), pk=pk)
    if record.photo.pk != photo_id:
        raise Http404
    return _photo_response(request, record.photo)


@require_POST
def record_guarantor_call(request, pk):
    record = get_object_or_404(Guarantor, pk=pk)
    return _run(
        request,
        record,
        lambda: review.record_call(
            record,
            staff=request.user,
            knows_jobber=request.POST.get("knows_jobber") == "on",
            confirms_residence=request.POST.get("confirms_residence") == "on",
            agrees_contact=request.POST.get("agrees_contact") == "on",
        ),
        "Appel enregistré.",
    )


@require_POST
def confirm_guarantor(request, pk):
    record = get_object_or_404(Guarantor, pk=pk)
    return _run(
        request,
        record,
        lambda: review.confirm_guarantor(
            record,
            staff=request.user,
            holder_name=request.POST.get("holder_name", ""),
            reference_number=request.POST.get("reference_number", ""),
            issued_on=_date(request, "issued_on"),
            name_matches=request.POST.get("name_matches") == "on",
        ),
        "Garant confirmé.",
    )


@require_POST
def refuse_guarantor(request, pk):
    record = get_object_or_404(Guarantor, pk=pk)
    return _run(
        request,
        record,
        lambda: review.refuse_guarantor(record, staff=request.user, reason=request.POST.get("reason", "")),
        "Garant refusé.",
    )


@require_GET
def guarantor_photo(request, pk, photo_id):
    record = get_object_or_404(Guarantor.objects.select_related("photo"), pk=pk)
    if record.photo.pk != photo_id:
        raise Http404
    return _photo_response(request, record.photo)


def _contact_link(contact, message: str) -> str:
    """The one-time WhatsApp link to the contact's number. The number is never written as text."""
    return registry.get_messaging().whatsapp_link(decrypt_text(contact.phone), message)


def _contact_page(request, contact, *, heading, intro, link, warning):
    response = render(
        request,
        "console/contact_send.html",
        {
            "heading": heading,
            "intro": intro,
            "whatsapp_link": link,
            "warning": warning,
            "official_number": settings.OFFICIAL_WHATSAPP_NUMBER or "non configuré",
            "back_url": reverse("admin:verification_trustedcontact_change", args=[contact.pk]),
            "title": heading,
        },
    )
    patch_cache_control(response, no_store=True)
    return response


def _contact_error(request, contact, exc: VerificationError, invalid_state: str):
    if exc.code == "forbidden":
        raise PermissionDenied from exc
    text = invalid_state if exc.code == "invalid_state" else MESSAGES.get(exc.code, exc.code)
    messages.error(request, text)
    return _back(contact)


@require_POST
def send_contact_code(request, pk):
    """Issue a code and show the WhatsApp link once."""
    contact = get_object_or_404(TrustedContact, pk=pk)
    try:
        code = contacts.send_code(contact, staff=request.user)
    except VerificationError as exc:
        return _contact_error(request, contact, exc, "Cette personne n'est plus à confirmer.")
    return _contact_page(
        request,
        contact,
        heading="Envoyer le code à la personne de confiance",
        intro=f"Personne : {decrypt_text(contact.name)}.",
        link=_contact_link(contact, contacts.CONTACT_MESSAGE.format(code=code)),
        warning="Ne recopiez pas ce code : il sera demandé au mini-jobber.",
    )


@require_POST
def notify_old_contact(request, pk):
    """Warn the number that is being replaced, and show the WhatsApp link once."""
    contact = get_object_or_404(TrustedContact, pk=pk)
    try:
        contacts.record_notice(contact, staff=request.user)
    except VerificationError as exc:
        return _contact_error(request, contact, exc, "Il n'y a rien à prévenir pour cette personne.")
    message = contacts.NOTICE_MESSAGE.format(n=settings.TRUSTED_CONTACT_CHANGE_DELAY_HOURS)
    return _contact_page(
        request,
        contact,
        heading="Prévenir l'ancienne personne de confiance",
        intro=f"Personne remplacée : {decrypt_text(contact.name)}.",
        link=_contact_link(contact, message),
        warning=f"Le remplacement prendra effet dans {settings.TRUSTED_CONTACT_CHANGE_DELAY_HOURS} h.",
    )
