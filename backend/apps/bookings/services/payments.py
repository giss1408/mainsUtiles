"""Payment for a booking. The platform has no payment API: householders pay a receiving number of
the platform, send proof, and staff check it against the platform account's real history. Every
rule lives here; views only translate HTTP."""

import re
from datetime import datetime, timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Payment, PaymentMethod
from apps.verification.services import submissions
from apps.verification.services.encryption import encrypt_text, keyed_hash

from .applications import BookingError

REFERENCE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 .\-]{2,38}[A-Za-z0-9]$")


def available() -> bool:
    """The service is provided only while at least one method is active with a number."""
    return PaymentMethod.objects.available().exists()


def instructions() -> list[dict]:
    """What a householder is told about where to pay. The platform's numbers are not secret."""
    return [
        {
            "id": method.pk,
            "provider": method.provider,
            "provider_label": method.get_provider_display(),
            "number": method.number,
            "account_name": method.account_name,
        }
        for method in PaymentMethod.objects.available()
    ]


def reference_hash(reference: str) -> str:
    """The same receipt typed with other case, spaces or dashes gives the same hash."""
    return keyed_hash(re.sub(r"[^A-Z0-9]", "", reference.upper()))


def payment_amount(booking: Booking) -> tuple[int, int]:
    """What the householder pays in total, and the part of it the platform keeps."""
    fee = booking.pay_xof * settings.PLATFORM_FEE_PERCENT // 100
    return booking.pay_xof + fee, fee


def pay_deadline(booking: Booking) -> datetime:
    """The end of the time to pay: the payment window, or the opening of the address release,
    whichever comes first."""
    window = booking.accepted_at + timedelta(hours=settings.PAYMENT_WINDOW_HOURS)
    release = booking.starts_at - timedelta(hours=settings.ADDRESS_RELEASE_HOURS)
    return min(window, release)


def _require_householder(user) -> None:
    if not (user and user.is_active and user.role == "householder"):
        raise BookingError("forbidden")


def _own_booking(user, booking_id) -> Booking:
    try:
        booking = Booking.objects.select_for_update().filter(pk=booking_id, householder=user).first()
    except (ValidationError, ValueError):
        booking = None
    if booking is None:
        raise BookingError("forbidden")
    return booking


def submit_proof(
    user, booking_id, *, method_id, reference: str, screenshot: bytes, captured_at: datetime
) -> Payment:
    """The householder says they paid: a method, the transaction reference and a screenshot. Staff
    check it; until then the booking waits in `payment_review`."""
    _require_householder(user)
    with transaction.atomic():
        booking = _own_booking(user, booking_id)
        if booking.status != Booking.Status.ACCEPTED:
            raise BookingError("invalid_state")
        if timezone.now() > pay_deadline(booking):
            raise BookingError("payment_window_closed")
        if not available():
            raise BookingError("payment_unavailable")
        method = (
            PaymentMethod.objects.available().filter(pk=method_id).first() if _is_int(method_id) else None
        )
        if method is None:
            raise BookingError("method_invalid")
        text = (reference or "").strip()
        if not REFERENCE_PATTERN.match(text):
            raise BookingError("reference_invalid")
        try:
            proof = submissions.store_photo(user, "payment_proof", screenshot, captured_at, None)
        except submissions.VerificationError as exc:
            raise BookingError(exc.code) from exc
        amount, fee = payment_amount(booking)
        try:
            payment = Payment.objects.create(
                booking=booking,
                method=method,
                amount_xof=amount,
                fee_xof=fee,
                reference=encrypt_text(text),
                reference_hash=reference_hash(text),
                proof=proof,
            )
            booking.status = Booking.Status.PAYMENT_REVIEW
            booking.save(update_fields=["status"])
        except Exception:
            # The database rolls back; the encrypted file on disk must not stay behind.
            submissions._path(proof.storage_name).unlink(missing_ok=True)
            raise
        audit(user, "booking.payment.submit", payment, booking=str(booking.pk), method=method.provider)
    return payment


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)
