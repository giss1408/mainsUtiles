"""Payment for a booking. The platform has no payment API: householders pay a receiving number of
the platform, send proof, and staff check it against the platform account's real history. Every
rule lives here; views only translate HTTP."""

import re
from datetime import datetime, timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Payment, PaymentMethod
from apps.verification.models import VerificationPhoto
from apps.verification.services import submissions
from apps.verification.services.encryption import encrypt_text, keyed_hash

from . import messages
from .errors import BookingError

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


# ---- Staff ------------------------------------------------------------------------------------

VERIFY = "bookings.verify_payment"


def _require_staff(staff, permission: str) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(permission)):
        raise BookingError("forbidden")


def _locked(payment: Payment) -> tuple[Payment, Booking]:
    """Both rows under a lock, so two staff members cannot decide the same payment."""
    row = Payment.objects.select_for_update().get(pk=payment.pk)
    booking = Booking.objects.select_for_update().get(pk=row.booking_id)
    return row, booking


def _undecided(row: Payment, booking: Booking) -> None:
    if row.status != Payment.Status.SUBMITTED or booking.status != Booking.Status.PAYMENT_REVIEW:
        raise BookingError("invalid_state")


def confirm_payment(payment: Payment, *, staff, amount_matches: bool, reference_matches: bool) -> None:
    """Staff checked the amount and the reference against the platform account's own history."""
    _require_staff(staff, VERIFY)
    try:
        with transaction.atomic():
            row, booking = _locked(payment)
            _undecided(row, booking)
            if not (amount_matches and reference_matches):
                raise BookingError("checks_required")
            used = Payment.objects.filter(
                reference_hash=row.reference_hash,
                status__in=(Payment.Status.CONFIRMED, Payment.Status.REFUND_DUE, Payment.Status.REFUNDED),
            ).exclude(pk=row.pk)
            if used.exists():
                raise BookingError("reference_used")
            row.status = Payment.Status.CONFIRMED
            row.decided_by = staff
            row.decided_at = timezone.now()
            row.save(update_fields=["status", "decided_by", "decided_at"])
            booking.status = Booking.Status.CONFIRMED
            booking.save(update_fields=["status"])
            audit(staff, "booking.payment.confirm", row, booking=str(booking.pk))
            messages.queue(messages.K.PAYMENT_CONFIRMED, booking=booking, to=booking.householder)
            messages.queue(messages.K.JOB_CONFIRMED, booking=booking, to=booking.jobber)
    except IntegrityError as exc:
        raise BookingError("reference_used") from exc
    payment.refresh_from_db()


def refuse_payment(payment: Payment, *, staff, reason: str) -> None:
    """The proof does not match: the booking goes back to waiting for a payment."""
    _require_staff(staff, VERIFY)
    text = (reason or "").strip()
    with transaction.atomic():
        row, booking = _locked(payment)
        _undecided(row, booking)
        if not text:
            raise BookingError("reason_required")
        row.status = Payment.Status.REFUSED
        row.reason = text
        row.decided_by = staff
        row.decided_at = timezone.now()
        row.save(update_fields=["status", "reason", "decided_by", "decided_at"])
        booking.status = Booking.Status.ACCEPTED
        booking.save(update_fields=["status"])
        audit(staff, "booking.payment.refuse", row, booking=str(booking.pk), reason=text)
        messages.queue(messages.K.PAYMENT_REFUSED, booking=booking, to=booking.householder)
    payment.refresh_from_db()


def read_proof(payment: Payment, *, staff) -> bytes:
    """The decrypted screenshot. Every view leaves an audit row."""
    _require_staff(staff, VERIFY)
    data = submissions.read_photo_bytes(payment.proof)
    audit(staff, "booking.payment.view_proof", payment, booking=str(payment.booking_id))
    return data


def proof_seen_before(payment: Payment) -> bool:
    """The same image was sent for another payment: a reason to look closer."""
    return VerificationPhoto.objects.filter(sha256=payment.proof.sha256).exclude(pk=payment.proof_id).exists()


def record_refund(payment: Payment, *, staff, reference: str) -> None:
    """Staff sent the money back and note the reference of that transfer."""
    _require_staff(staff, "bookings.make_refund")
    text = (reference or "").strip()
    with transaction.atomic():
        row = Payment.objects.select_for_update().get(pk=payment.pk)
        if row.status != Payment.Status.REFUND_DUE:
            raise BookingError("invalid_state")
        if not text:
            raise BookingError("reference_invalid")
        row.status = Payment.Status.REFUNDED
        row.refund_reference = encrypt_text(text)
        row.refunded_by = staff
        row.refunded_at = timezone.now()
        row.save(update_fields=["status", "refund_reference", "refunded_by", "refunded_at"])
        audit(
            staff, "booking.payment.refund", row, booking=str(row.booking_id), amount_xof=refund_amount(row)
        )
        messages.queue(messages.K.REFUNDED, booking=row.booking, to=row.booking.householder)
    payment.refresh_from_db()


def refund_amount(payment: Payment) -> int:
    """What staff send back: the part decided in a split dispute, otherwise everything paid."""
    return payment.refund_xof if payment.refund_xof is not None else payment.amount_xof


def check_queue():
    """Payments waiting for staff to check them, oldest first."""
    return Payment.objects.filter(status=Payment.Status.SUBMITTED).select_related("booking", "method")


def refund_queue():
    """Cancelled payments waiting for staff to send the money back, oldest first."""
    return Payment.objects.filter(status=Payment.Status.REFUND_DUE).select_related("booking", "method")


def is_late(payment: Payment) -> bool:
    """A payment waiting longer than PAYMENT_REVIEW_LATE_HOURS for a decision."""
    waited = timezone.now() - payment.submitted_at
    return payment.status == Payment.Status.SUBMITTED and waited > timedelta(
        hours=settings.PAYMENT_REVIEW_LATE_HOURS
    )
