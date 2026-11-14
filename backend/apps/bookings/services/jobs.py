"""The job itself: the jobber arrives, finishes, the householder confirms, and what happens when
nobody does. Every rule lives here; views only translate HTTP."""

import math
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Payment, Payout, Report
from apps.listings.models import Offer
from apps.verification.models import HomeLocation, Status
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.tiers import current_record

from . import messages
from .bookings import _booking_of
from .errors import BookingError

EARTH_RADIUS_M = 6_371_000


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> int:
    """The distance in metres between two (latitude, longitude) points, by the haversine formula."""
    lat1, lng1, lat2, lng2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2
    return round(2 * EARTH_RADIUS_M * math.asin(math.sqrt(h)))


def needs_a_look(booking: Booking) -> bool:
    """The check-in happened far from the home pin: staff may want to ask why."""
    return (
        booking.checkin_distance_m is not None and booking.checkin_distance_m > settings.CHECKIN_FLAG_METERS
    )


def _valid(lat, lng) -> bool:
    return (
        isinstance(lat, int | float)
        and isinstance(lng, int | float)
        and -90 <= lat <= 90
        and -180 <= lng <= 180
    )


def _home_pin(booking: Booking):
    place = current_record(HomeLocation, booking.householder)
    if place is None or place.status != Status.CONFIRMED:
        return None
    return float(decrypt_text(place.latitude)), float(decrypt_text(place.longitude))


def checkin_from(booking: Booking):
    """The earliest moment the jobber may say they arrived."""
    return booking.starts_at - timedelta(minutes=settings.CHECKIN_EARLY_MINUTES)


def check_in(user, booking_id, *, lat, lng, accuracy_m=None) -> Booking:
    """The jobber says they arrived. The position, when the phone gave one, is compared with the
    home pin and only recorded: a far check-in is flagged for staff, never refused."""
    booking = _booking_of(user, booking_id, as_role="jobber")
    now = timezone.now()
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking.pk)
        if booking.status not in (Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED):
            raise BookingError("invalid_state")
        if now < checkin_from(booking):
            raise BookingError("checkin_too_early")
        if now >= booking.starts_at + timedelta(minutes=booking.duration_minutes):
            raise BookingError("checkin_closed")
        distance = None
        pin = _home_pin(booking)
        if pin is not None and _valid(lat, lng):
            distance = distance_m((float(lat), float(lng)), pin)
        booking.status = Booking.Status.CHECKED_IN
        booking.checked_in_at = now
        booking.checkin_distance_m = distance
        booking.save(update_fields=["status", "checked_in_at", "checkin_distance_m"])
        audit(user, "booking.check_in", booking, distance_m=distance, accuracy_m=accuracy_m)
    return booking


def check_out(user, booking_id) -> Booking:
    """The jobber says the job is done. The householder now has time to confirm."""
    booking = _booking_of(user, booking_id, as_role="jobber")
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking.pk)
        if booking.status != Booking.Status.CHECKED_IN:
            raise BookingError("invalid_state")
        booking.status = Booking.Status.COMPLETION_PENDING
        booking.checked_out_at = timezone.now()
        booking.save(update_fields=["status", "checked_out_at"])
        audit(user, "booking.check_out", booking)
        messages.queue(messages.K.CONFIRM_JOB, booking=booking, to=booking.householder)
    return booking


# ---- Closing the job ---------------------------------------------------------------------------


def _complete(booking: Booking, *, how: str, actor) -> None:
    """Mark the booking completed and owe the jobber their pay, once."""
    booking.status = Booking.Status.COMPLETED
    booking.completed_at = timezone.now()
    booking.completion = how
    booking.save(update_fields=["status", "completed_at", "completion"])
    Payout.objects.get_or_create(booking=booking, defaults={"amount_xof": booking.pay_xof})
    audit(actor, "booking.complete", booking, how=how)
    invite_reviews(booking)


def invite_reviews(booking: Booking) -> None:
    """Both sides are asked for a review once the job is completed."""
    messages.queue(messages.K.REVIEW_INVITE, booking=booking, to=booking.householder)
    messages.queue(messages.K.REVIEW_INVITE, booking=booking, to=booking.jobber)


def confirm_done(user, booking_id) -> Booking:
    """The householder says the job was done. The platform now owes the jobber."""
    booking = _booking_of(user, booking_id, as_role="householder")
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking.pk)
        if booking.status != Booking.Status.COMPLETION_PENDING:
            raise BookingError("invalid_state")
        _complete(booking, how="householder", actor=user)
    return booking


def complete_overdue(now=None) -> int:
    """The householder did not answer in time: the job counts as done."""
    now = now or timezone.now()
    cutoff = now - timedelta(hours=settings.RELEASE_TIMEOUT_HOURS)
    count = 0
    for found in list(
        Booking.objects.filter(status=Booking.Status.COMPLETION_PENDING, checked_out_at__lt=cutoff)
    ):
        with transaction.atomic():
            booking = Booking.objects.select_for_update().get(pk=found.pk)
            if booking.status != Booking.Status.COMPLETION_PENDING:
                continue
            _complete(booking, how="timeout", actor=None)
            count += 1
    return count


def close_no_shows(now=None) -> int:
    """A paid booking whose time is over and where nobody checked in: the money goes back."""
    now = now or timezone.now()
    count = 0
    candidates = Booking.objects.filter(
        status__in=(Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED), checked_in_at__isnull=True
    )
    for found in list(candidates):
        if now < found.starts_at + timedelta(minutes=found.duration_minutes):
            continue
        with transaction.atomic():
            booking = Booking.objects.select_for_update().get(pk=found.pk)
            if booking.status not in (Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED):
                continue
            booking.status = Booking.Status.CANCELLED
            booking.cancelled_at = now
            booking.cancel_reason = "no_show"
            booking.save(update_fields=["status", "cancelled_at", "cancel_reason"])
            Payment.objects.filter(
                booking=booking, status__in=(Payment.Status.SUBMITTED, Payment.Status.CONFIRMED)
            ).update(status=Payment.Status.REFUND_DUE)
            Offer.objects.filter(pk=booking.offer_id, status=Offer.Status.BOOKED).update(
                status=Offer.Status.CLOSED, updated_at=now
            )
            audit(None, "booking.no_show", booking)
            messages.queue(messages.K.NO_SHOW, booking=booking, to=booking.householder)
            count += 1
    return count


def flag_unclosed(now=None) -> int:
    """A jobber who arrived and never left: staff look at it, nobody is paid meanwhile."""
    now = now or timezone.now()
    count = 0
    for found in list(Booking.objects.filter(status=Booking.Status.CHECKED_IN)):
        end = found.starts_at + timedelta(minutes=found.duration_minutes)
        if now < end + timedelta(hours=settings.CHECKOUT_GRACE_HOURS):
            continue
        with transaction.atomic():
            booking = Booking.objects.select_for_update().get(pk=found.pk)
            if booking.status != Booking.Status.CHECKED_IN:
                continue
            booking.status = Booking.Status.DISPUTED
            booking.save(update_fields=["status"])
            Report.objects.get_or_create(
                booking=booking,
                kind=Report.Kind.DISPUTE,
                status=Report.Status.OPEN,
                defaults={"author": booking.jobber, "text": "Pas de départ enregistré"},
            )
            audit(None, "booking.unclosed", booking)
            messages.queue(messages.K.DISPUTE_OPENED, booking=booking, to=booking.householder)
            messages.queue(messages.K.DISPUTE_OPENED, booking=booking, to=booking.jobber)
            count += 1
    return count
