"""Paying the jobber: staff send the money by hand and record the reference. A payout is made once,
and never for a booking whose payment was refunded or is waiting to be."""

import re

from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Payment, Payout
from apps.verification.services.encryption import encrypt_text

from .errors import BookingError
from .payments import _require_staff

PAY = "bookings.make_payout"
REFERENCE_PATTERN = re.compile(r"^[A-Za-z0-9 .\-]{4,40}$")


def _payable(payment: Payment) -> bool:
    """The householder's money is still held for the jobber: the payment is confirmed, or a split
    dispute sends back only a part of it. A booking refunded in full is never paid."""
    if payment.status == Payment.Status.CONFIRMED:
        return True
    partial = payment.refund_xof is not None
    return partial and payment.status in (Payment.Status.REFUND_DUE, Payment.Status.REFUNDED)


def _payment_of(payout: Payout) -> Payment:
    """The payment that paid for the booking (a refused proof is not one)."""
    found = (
        Payment.objects.select_for_update()
        .filter(booking_id=payout.booking_id)
        .exclude(status__in=(Payment.Status.SUBMITTED, Payment.Status.REFUSED))
        .first()
    )
    if found is None:
        raise BookingError("invalid_state")
    return found


def payable(payout: Payout) -> bool:
    """The money for this payout is still held: False once the booking was refunded in full."""
    payment = (
        Payment.objects.filter(booking_id=payout.booking_id)
        .exclude(status__in=(Payment.Status.SUBMITTED, Payment.Status.REFUSED))
        .first()
    )
    return payment is not None and _payable(payment)


def payout_queue(*, staff):
    """Payouts waiting for staff, oldest first."""
    _require_staff(staff, PAY)
    return Payout.objects.filter(status=Payout.Status.DUE).select_related("booking").order_by("due_at")


def payout_details(payout: Payout, *, staff) -> dict:
    """What staff need to send the money, including the jobber's phone. Audited at every view."""
    _require_staff(staff, PAY)
    booking = payout.booking
    audit(staff, "booking.payout.view", payout, booking=str(booking.pk))
    return {
        "amount_xof": payout.amount_xof,
        "jobber_phone": booking.jobber.phone,
        "category_name": booking.category_name,
        "completed_at": booking.completed_at,
    }


def record_payout(payout: Payout, *, staff, reference: str) -> None:
    """Staff sent the money and note the reference of that transfer."""
    _require_staff(staff, PAY)
    text = (reference or "").strip()
    with transaction.atomic():
        row = Payout.objects.select_for_update().get(pk=payout.pk)
        if row.status != Payout.Status.DUE:
            raise BookingError("invalid_state")
        payment = _payment_of(row)
        if not _payable(payment):
            raise BookingError("invalid_state")
        if not REFERENCE_PATTERN.match(text):
            raise BookingError("reference_invalid")
        row.status = Payout.Status.PAID
        row.reference = encrypt_text(text)
        row.paid_by = staff
        row.paid_at = timezone.now()
        row.save(update_fields=["status", "reference", "paid_by", "paid_at"])
        audit(staff, "booking.payout.pay", row, booking=str(row.booking_id))
    payout.refresh_from_db()
