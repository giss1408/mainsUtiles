"""Householders' job offers: drafts, sending, withdrawing, and the clean-up of past ones."""

from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

from django.conf import settings
from django.db import transaction
from django.db.models import Count
from django.utils import timezone

from apps.listings.models import Offer, OfferCategory
from apps.listings.services.screening import screen
from apps.verification.models import AddressProof
from apps.verification.services.tiers import current_record, householder_tier

ABIDJAN = ZoneInfo("Africa/Abidjan")
WITHDRAWN_UNVERIFIED = "Votre compte n'est plus vérifié. Renouvelez votre justificatif de domicile."


class OfferError(Exception):
    """A rule was broken. `code` is mapped to a status and a French message by the callers."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _require_householder(user) -> None:
    if not (user and user.is_active and user.role == "householder"):
        raise OfferError("forbidden")


def _require_owner(offer: Offer, user) -> None:
    _require_householder(user)
    if offer.author_id != user.pk:
        raise OfferError("forbidden")


def _require_verified(user) -> None:
    if householder_tier(user) != "H1":
        raise OfferError("verification_required")


def _hm(value: str) -> time:
    hour, minute = value.split(":")
    return time(int(hour), int(minute))


def _validate(
    *,
    category_id,
    duties,
    starts_at: datetime,
    duration_minutes: int,
    pay_xof: int,
    note: str,
) -> OfferCategory:
    """Every rule that does not depend on the moment of sending."""
    category = OfferCategory.objects.filter(pk=category_id, active=True).first()
    if category is None:
        raise OfferError("category_invalid")
    if not isinstance(duties, list) or not duties:
        raise OfferError("duties_invalid")
    cleaned = [duty.strip() if isinstance(duty, str) else "" for duty in duties]
    if any(duty not in category.duties for duty in cleaned) or len(set(cleaned)) != len(cleaned):
        raise OfferError("duties_invalid")
    if duration_minutes not in category.durations_minutes:
        raise OfferError("duration_invalid")
    if not (settings.OFFER_MIN_PAY_XOF <= pay_xof <= settings.OFFER_MAX_PAY_XOF):
        raise OfferError("pay_invalid")
    if len(note) > settings.OFFER_NOTE_MAX_LENGTH:
        raise OfferError("note_too_long")
    now = timezone.now()
    if starts_at <= now or starts_at > now + timedelta(days=settings.OFFER_MAX_DAYS_AHEAD):
        raise OfferError("time_invalid")
    local_start = starts_at.astimezone(ABIDJAN)
    local_end = local_start + timedelta(minutes=duration_minutes)
    if local_start.time() < _hm(settings.OFFER_EARLIEST_START):
        raise OfferError("time_invalid")
    if local_end.date() != local_start.date() or local_end.time() > _hm(settings.OFFER_LATEST_END):
        raise OfferError("time_invalid")
    return category


def _fields(values: dict) -> dict:
    return {
        "duties": [duty.strip() for duty in values["duties"]],
        "starts_at": values["starts_at"],
        "duration_minutes": values["duration_minutes"],
        "pay_xof": values["pay_xof"],
        "note": values.get("note", "").strip(),
    }


def create_draft(
    user,
    *,
    category_id,
    duties: list[str],
    starts_at: datetime,
    duration_minutes: int,
    pay_xof: int,
    note: str = "",
) -> Offer:
    _require_householder(user)
    _require_verified(user)
    values = {
        "category_id": category_id,
        "duties": duties,
        "starts_at": starts_at,
        "duration_minutes": duration_minutes,
        "pay_xof": pay_xof,
        "note": note.strip(),
    }
    _validate(**values)
    return Offer.objects.create(author=user, category_id=category_id, **_fields(values))


def update_draft(offer: Offer, *, user, **changes) -> Offer:
    with transaction.atomic():
        row = Offer.objects.select_for_update().get(pk=offer.pk)
        _require_owner(row, user)
        _require_verified(user)
        if row.status != Offer.Status.DRAFT:
            raise OfferError("invalid_state")
        values = {
            "category_id": changes.get("category_id", row.category_id),
            "duties": changes.get("duties", row.duties),
            "starts_at": changes.get("starts_at", row.starts_at),
            "duration_minutes": changes.get("duration_minutes", row.duration_minutes),
            "pay_xof": changes.get("pay_xof", row.pay_xof),
            "note": changes.get("note", row.note),
        }
        values["note"] = values["note"].strip()
        _validate(**values)
        for field, value in _fields(values).items():
            setattr(row, field, value)
        row.category_id = values["category_id"]
        row.save()
    offer.refresh_from_db()
    return offer


def delete_draft(offer: Offer, *, user) -> None:
    with transaction.atomic():
        row = Offer.objects.select_for_update().get(pk=offer.pk)
        _require_owner(row, user)
        if row.status != Offer.Status.DRAFT:
            raise OfferError("invalid_state")
        row.delete()


def send(offer: Offer, *, user) -> Offer:
    """Check every rule again, copy the place and the category, then publish or send to review."""
    with transaction.atomic():
        row = Offer.objects.select_for_update().get(pk=offer.pk)
        _require_owner(row, user)
        _require_verified(user)
        if row.status != Offer.Status.DRAFT:
            raise OfferError("invalid_state")
        category = _validate(
            category_id=row.category_id,
            duties=row.duties,
            starts_at=row.starts_at,
            duration_minutes=row.duration_minutes,
            pay_xof=row.pay_xof,
            note=row.note,
        )
        open_count = Offer.objects.filter(author=user, status__in=Offer.OPEN_STATUSES).count()
        if open_count >= settings.OFFER_MAX_OPEN_PER_HOUSEHOLDER:
            raise OfferError("too_many_offers")
        first_offer = not Offer.objects.filter(author=user, sent_at__isnull=False).exists()
        flags = screen(category=category, pay_xof=row.pay_xof, note=row.note, first_offer=first_offer)
        place = current_record(AddressProof, user)
        now = timezone.now()
        row.category_name = category.name
        row.commune = place.commune
        row.quartier = place.quartier
        row.flags = flags
        row.sent_at = now
        if flags:
            row.status = Offer.Status.IN_REVIEW
        else:
            row.status = Offer.Status.PUBLISHED
            row.published_at = now
        row.save()
    offer.refresh_from_db()
    return offer


def withdraw(offer: Offer, *, user) -> Offer:
    with transaction.atomic():
        row = Offer.objects.select_for_update().get(pk=offer.pk)
        _require_owner(row, user)
        if row.status not in (
            Offer.Status.DRAFT,
            Offer.Status.IN_REVIEW,
            Offer.Status.PUBLISHED,
            Offer.Status.BOOKED,
        ):
            raise OfferError("invalid_state")
        if row.status == Offer.Status.BOOKED:
            _cancel_unpaid_booking(row, user)
        row.status = Offer.Status.WITHDRAWN
        row.save(update_fields=["status", "updated_at"])
    offer.refresh_from_db()
    return offer


def _cancel_unpaid_booking(offer: Offer, user) -> None:
    """Withdrawing a booked offer cancels its booking while the booking is not confirmed: an unpaid
    one, or one whose proof is still under review (the payment then becomes a refund to make).
    Once the booking is confirmed, only cancelling the booking itself can end it."""
    from apps.bookings.models import Booking
    from apps.bookings.services import bookings

    booking = Booking.objects.select_for_update().filter(offer=offer, status__in=Booking.LIVE).first()
    if booking is None:
        return
    if booking.status not in (Booking.Status.ACCEPTED, Booking.Status.PAYMENT_REVIEW):
        raise OfferError("invalid_state")
    bookings.cancel(user, booking.pk, reason="offre retirée")


def copy_as_draft(offer: Offer, *, user) -> Offer:
    """A new draft with the same content, its date moved to the next day that is still ahead."""
    _require_owner(offer, user)
    _require_verified(user)
    start = offer.starts_at.astimezone(ABIDJAN)
    candidate = start
    while candidate.astimezone(UTC) <= timezone.now():
        candidate += timedelta(days=1)
    return Offer.objects.create(
        author=user,
        category=offer.category,
        duties=list(offer.duties),
        starts_at=candidate.astimezone(UTC),
        duration_minutes=offer.duration_minutes,
        pay_xof=offer.pay_xof,
        note=offer.note,
    )


def visible_to_jobbers():
    """Published offers whose start is still ahead, soonest first."""
    return Offer.objects.filter(status=Offer.Status.PUBLISHED, starts_at__gt=timezone.now()).order_by(
        "starts_at"
    )


def tidy() -> dict:
    """Close offers whose start has passed; withdraw open offers of householders no longer verified."""
    now = timezone.now()
    closed = Offer.objects.filter(status=Offer.Status.PUBLISHED, starts_at__lte=now).update(
        status=Offer.Status.CLOSED
    )
    expired = _expire_unpaid_bookings(now)
    withdrawn = 0
    open_offers = (
        Offer.objects.filter(status__in=Offer.OPEN_STATUSES).values("author_id").annotate(n=Count("id"))
    )
    for entry in open_offers:
        user_pk = entry["author_id"]
        from apps.accounts.models import User

        owner = User.objects.get(pk=user_pk)
        if householder_tier(owner) != "H1":
            withdrawn += Offer.objects.filter(author_id=user_pk, status__in=Offer.OPEN_STATUSES).update(
                status=Offer.Status.WITHDRAWN, reason=WITHDRAWN_UNVERIFIED, updated_at=now
            )
    return {"closed": closed, "withdrawn": withdrawn, "expired": expired}


def _expire_unpaid_bookings(now) -> int:
    """A booked offer whose start has passed with nothing paid is over: the booking expires and the
    offer closes. A booking that moved on is left to its own rules."""
    from apps.bookings.models import Booking

    unpaid = Booking.objects.filter(
        offer__status=Offer.Status.BOOKED, offer__starts_at__lte=now, status=Booking.Status.ACCEPTED
    )
    offer_ids = list(unpaid.values_list("offer_id", flat=True))
    count = unpaid.update(status=Booking.Status.EXPIRED)
    Offer.objects.filter(pk__in=offer_ids).update(status=Offer.Status.CLOSED, updated_at=now)
    return count
