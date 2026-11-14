"""The job itself: the jobber arrives, finishes, the householder confirms, and what happens when
nobody does. Every rule lives here; views only translate HTTP."""

import math
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking
from apps.verification.models import HomeLocation, Status
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.tiers import current_record

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


def check_in(user, booking_id, *, lat, lng, accuracy_m=None) -> Booking:
    """The jobber says they arrived. The position, when the phone gave one, is compared with the
    home pin and only recorded: a far check-in is flagged for staff, never refused."""
    booking = _booking_of(user, booking_id, as_role="jobber")
    now = timezone.now()
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking.pk)
        if booking.status not in (Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED):
            raise BookingError("invalid_state")
        if now < booking.starts_at - timedelta(minutes=settings.CHECKIN_EARLY_MINUTES):
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
    return booking
