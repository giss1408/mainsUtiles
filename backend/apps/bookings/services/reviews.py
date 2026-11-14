"""Reviews after a completed booking, both ways. One side's review stays hidden until the other is
in or the window ends, so nobody answers a bad review with another, and nobody is pressed."""

from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Avg, Count
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Review
from apps.listings.services.screening import contact_in

from .errors import BookingError
from .reports import _party_booking


def _window_end(booking: Booking):
    return booking.completed_at + timedelta(days=settings.REVIEW_WINDOW_DAYS)


def reviewable(booking: Booking, user, now=None) -> bool:
    """This party may still send a review for the booking."""
    now = now or timezone.now()
    return (
        booking.status == Booking.Status.COMPLETED
        and booking.completed_at is not None
        and now <= _window_end(booking)
        and not Review.objects.filter(booking=booking, author=user).exists()
    )


def submit_review(user, booking_id, *, stars: int, comment: str = "") -> Review:
    """A party of a completed booking rates the other one, once."""
    found = _party_booking(user, booking_id)
    now = timezone.now()
    try:
        with transaction.atomic():
            booking = Booking.objects.select_for_update().get(pk=found.pk)
            if booking.status != Booking.Status.COMPLETED or booking.completed_at is None:
                raise BookingError("invalid_state")
            if Review.objects.filter(booking=booking, author=user).exists():
                raise BookingError("already_reviewed")
            if now > _window_end(booking):
                raise BookingError("review_closed")
            if isinstance(stars, bool) or not isinstance(stars, int) or not 1 <= stars <= 5:
                raise BookingError("stars_invalid")
            text = (comment or "").strip()
            if len(text) > settings.REVIEW_COMMENT_MAX:
                raise BookingError("message_too_long")
            if text and contact_in(text):
                raise BookingError("message_contact_details")
            about_id = booking.jobber_id if user.pk == booking.householder_id else booking.householder_id
            review = Review.objects.create(
                booking=booking, author=user, about_id=about_id, stars=stars, comment=text
            )
            if Review.objects.filter(booking=booking).count() == 2:
                Review.objects.filter(booking=booking, published_at__isnull=True).update(published_at=now)
                review.refresh_from_db()
            audit(user, "booking.review", review, booking=str(booking.pk))
    except IntegrityError:
        raise BookingError("already_reviewed") from None
    return review


def publish_due(now=None) -> int:
    """Reviews whose window ended without the other side's are published alone."""
    now = now or timezone.now()
    cutoff = now - timedelta(days=settings.REVIEW_WINDOW_DAYS)
    return Review.objects.filter(published_at__isnull=True, booking__completed_at__lt=cutoff).update(
        published_at=now
    )


def _item(review: Review | None) -> dict | None:
    return None if review is None else {"stars": review.stars, "comment": review.comment}


def my_review_state(user, booking_id) -> dict:
    """The user's own review and, only once published, the other side's."""
    booking = _party_booking(user, booking_id)
    mine = Review.objects.filter(booking=booking, author=user).first()
    theirs = Review.objects.filter(booking=booking, about=user, published_at__isnull=False).first()
    return {"mine": _item(mine), "theirs": _item(theirs)}


def rating_of(user) -> dict:
    """The average and the number of published reviews about the user."""
    found = Review.objects.filter(about=user, published_at__isnull=False).aggregate(
        average=Avg("stars"), count=Count("id")
    )
    average = found["average"]
    return {"average": None if average is None else round(float(average), 1), "count": found["count"]}


def ratings_of(user_ids) -> dict:
    """The average published rating of each user who has one."""
    rows = (
        Review.objects.filter(about_id__in=user_ids, published_at__isnull=False)
        .values("about_id")
        .annotate(average=Avg("stars"))
    )
    return {row["about_id"]: round(float(row["average"]), 1) for row in rows}
