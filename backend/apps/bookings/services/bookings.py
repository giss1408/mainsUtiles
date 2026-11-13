"""A booking's life after it is accepted: cancelling, expiring when nothing was paid, and the
release of the address. Every rule lives here; views only translate HTTP."""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Payment
from apps.listings.models import Offer

from .errors import BookingError

CANCELLABLE = (
    Booking.Status.ACCEPTED,
    Booking.Status.PAYMENT_REVIEW,
    Booking.Status.CONFIRMED,
    Booking.Status.ADDRESS_RELEASED,
)


def _reopen_or_close(offer_id, now) -> None:
    """The offer is offered again if its start is still ahead, otherwise it is over."""
    offer = Offer.objects.select_for_update().get(pk=offer_id)
    if offer.status != Offer.Status.BOOKED:
        return  # withdrawn or closed meanwhile: leave it as it is
    offer.status = Offer.Status.PUBLISHED if offer.starts_at > now else Offer.Status.CLOSED
    offer.save(update_fields=["status", "updated_at"])


def cancel(user, booking_id, *, reason: str = "") -> Booking:
    """The householder or the jobber ends the booking before check-in. Money that may have been
    sent becomes a refund for staff to make."""
    if not (user and user.is_active and user.role in ("householder", "jobber")):
        raise BookingError("forbidden")
    try:
        found = Booking.objects.filter(pk=booking_id).first()
    except (ValidationError, ValueError):
        found = None
    if found is None or user.pk not in (found.householder_id, found.jobber_id):
        raise BookingError("forbidden")
    now = timezone.now()
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=found.pk)
        if booking.status not in CANCELLABLE:
            raise BookingError("invalid_state")
        booking.status = Booking.Status.CANCELLED
        booking.cancelled_by = user
        booking.cancelled_at = now
        booking.cancel_reason = (reason or "").strip()[:500]
        booking.save(update_fields=["status", "cancelled_by", "cancelled_at", "cancel_reason"])
        Payment.objects.filter(
            booking=booking, status__in=(Payment.Status.SUBMITTED, Payment.Status.CONFIRMED)
        ).update(status=Payment.Status.REFUND_DUE)
        _reopen_or_close(booking.offer_id, now)
        audit(user, "booking.cancel", booking, reason=booking.cancel_reason)
    return booking


def expire_unpaid(now=None) -> int:
    """Bookings with no proof of payment, past the payment window or the release time, expire. A
    booking whose proof is under review is never touched: staff are expected to answer."""
    now = now or timezone.now()
    from django.db.models import Q

    due = Booking.objects.filter(status=Booking.Status.ACCEPTED).filter(
        Q(accepted_at__lt=now - timedelta(hours=settings.PAYMENT_WINDOW_HOURS))
        | Q(starts_at__lt=now + timedelta(hours=settings.ADDRESS_RELEASE_HOURS))
    )
    count = 0
    for found in list(due):
        with transaction.atomic():
            booking = Booking.objects.select_for_update().get(pk=found.pk)
            if booking.status != Booking.Status.ACCEPTED:
                continue
            booking.status = Booking.Status.EXPIRED
            booking.save(update_fields=["status"])
            _reopen_or_close(booking.offer_id, now)
            audit(None, "booking.expire", booking)
            count += 1
    return count
