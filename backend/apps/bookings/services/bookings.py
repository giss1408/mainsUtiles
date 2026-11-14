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
from apps.verification.models import HomeLocation, IdentityVerification, Status
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import read_photo_bytes
from apps.verification.services.tiers import current_record

from . import messages
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
        other = booking.jobber if user.pk == booking.householder_id else booking.householder
        messages.queue(messages.K.CANCELLED, booking=booking, to=other)
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
            messages.queue(messages.K.EXPIRED, booking=booking, to=booking.jobber)
            count += 1
    return count


# ---- What each side learns once the booking is paid ------------------------------------------

RELEASABLE = (Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED)
KNOWN_AFTER_PAYMENT = (
    Booking.Status.CONFIRMED,
    Booking.Status.ADDRESS_RELEASED,
    Booking.Status.CHECKED_IN,
    Booking.Status.COMPLETION_PENDING,
    Booking.Status.DISPUTED,
    Booking.Status.COMPLETED,
)


def available_from(booking: Booking):
    """When the exact pin is shown to the jobber."""
    return booking.starts_at - timedelta(hours=settings.ADDRESS_RELEASE_HOURS)


def _booking_of(user, booking_id, *, as_role: str) -> Booking:
    if not (user and user.is_active and user.role == as_role):
        raise BookingError("forbidden")
    who = "jobber" if as_role == "jobber" else "householder"
    try:
        booking = Booking.objects.filter(pk=booking_id, **{who: user}).first()
    except (ValidationError, ValueError):
        booking = None
    if booking is None:
        raise BookingError("forbidden")
    return booking


def address_for(user, booking_id) -> dict:
    """The exact pin, for the booked jobber only, only in the release window. Every read is audited."""
    booking = _booking_of(user, booking_id, as_role="jobber")
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=booking.pk)
        if booking.status not in RELEASABLE:
            raise BookingError("invalid_state")
        now = timezone.now()
        if now < available_from(booking):
            raise BookingError("address_not_yet")
        if now >= booking.starts_at + timedelta(minutes=booking.duration_minutes):
            raise BookingError("address_closed")
        place = current_record(HomeLocation, booking.householder)
        if place is None or place.status != Status.CONFIRMED:
            raise BookingError("invalid_state")
        if booking.status == Booking.Status.CONFIRMED:
            booking.status = Booking.Status.ADDRESS_RELEASED
            booking.save(update_fields=["status"])
        audit(user, "booking.address.release", booking)
        return {
            "latitude": float(decrypt_text(place.latitude)),
            "longitude": float(decrypt_text(place.longitude)),
            "commune": booking.commune,
            "quartier": booking.quartier,
        }


def _confirmed_identity(booking: Booking) -> IdentityVerification:
    identity = current_record(IdentityVerification, booking.jobber)
    if identity is None or identity.status != Status.CONFIRMED:
        raise BookingError("invalid_state")
    return identity


def jobber_card(user, booking_id) -> dict:
    """The jobber's full name, for the householder, once the booking is paid. Audited."""
    booking = _booking_of(user, booking_id, as_role="householder")
    if booking.status not in KNOWN_AFTER_PAYMENT:
        raise BookingError("invalid_state")
    identity = _confirmed_identity(booking)
    audit(user, "booking.jobber.view", booking)
    return {"full_name": decrypt_text(identity.full_name), "has_photo": True}


def jobber_photo(user, booking_id) -> bytes:
    """The jobber's verified photo, for the householder, once the booking is paid. Audited."""
    booking = _booking_of(user, booking_id, as_role="householder")
    if booking.status not in KNOWN_AFTER_PAYMENT:
        raise BookingError("invalid_state")
    identity = _confirmed_identity(booking)
    data = read_photo_bytes(identity.selfie)
    audit(user, "booking.jobber.view_photo", booking)
    return data


# ---- What the apps show ------------------------------------------------------------------------


def live_booking(user, offer_id) -> Booking:
    if not (user and user.is_active and user.role == "householder"):
        raise BookingError("forbidden")
    try:
        booking = (
            Booking.objects.filter(offer_id=offer_id, householder=user, status__in=Booking.LIVE)
            .order_by("-created_at")
            .first()
        )
    except (ValidationError, ValueError):
        booking = None
    if booking is None:
        raise BookingError("forbidden")
    return booking


def offer_booking(user, offer_id) -> Booking:
    """The offer's live booking or, once the job is over, its completed one."""
    try:
        return live_booking(user, offer_id)
    except BookingError:
        done = (
            Booking.objects.filter(offer_id=offer_id, householder=user, status=Booking.Status.COMPLETED)
            .order_by("-created_at")
            .first()
        )
        if done is None:
            raise
        return done


def auto_confirm_at(booking: Booking):
    """When a job waiting for the householder's confirmation completes by itself."""
    if booking.status != Booking.Status.COMPLETION_PENDING or booking.checked_out_at is None:
        return None
    return booking.checked_out_at + timedelta(hours=settings.RELEASE_TIMEOUT_HOURS)


def payout_state(booking: Booking) -> str:
    """`none`, `due` or `paid`: what the jobber may know about their pay."""
    from apps.bookings.models import Payout

    payout = Payout.objects.filter(booking=booking).first()
    return "none" if payout is None else payout.status


def householder_view(user, offer_id) -> dict:
    """The booking of one of the householder's offers, with what they need to pay and follow it."""
    from . import payments, reviews
    from .applications import first_names

    booking = offer_booking(user, offer_id)
    amount, fee = payments.payment_amount(booking)
    last = booking.payments.order_by("-submitted_at").first()
    if booking.status in KNOWN_AFTER_PAYMENT:
        jobber = jobber_card(user, booking.pk)
    else:
        jobber = {"first_name": first_names([booking.jobber_id]).get(booking.jobber_id, "")}
    return {
        "id": booking.pk,
        "status": booking.status,
        "amount_xof": amount,
        "fee_xof": fee,
        "pay_deadline": payments.pay_deadline(booking),
        "methods": payments.instructions(),
        "payment": {"status": last.status, "reason": last.reason} if last else None,
        "jobber": jobber,
        "cancellable": booking.status in CANCELLABLE,
        "checked_in_at": booking.checked_in_at,
        "checked_out_at": booking.checked_out_at,
        "auto_confirm_at": auto_confirm_at(booking),
        "reviewable": reviews.reviewable(booking, user),
        "jobber_rating": reviews.rating_of(booking.jobber)["average"],
    }


def jobber_payment_state(booking: Booking) -> str:
    """`pending` until a proof is sent, `review` while staff check it, `confirmed` after."""
    if booking.status == Booking.Status.ACCEPTED:
        return "pending"
    if booking.status == Booking.Status.PAYMENT_REVIEW:
        return "review"
    return "confirmed"


def householder_photo(user, offer_id) -> bytes:
    return jobber_photo(user, offer_booking(user, offer_id).pk)
