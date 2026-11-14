from datetime import timedelta

import pytest
from django.utils import timezone

from apps.bookings.models import Booking, Review
from apps.bookings.services import applications, jobs, reviews
from apps.bookings.services.errors import BookingError
from tests.helpers import confirmed_booking, j1_jobber, make_offer

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


@pytest.fixture
def confirmed(verified_householder, jpeg, verifier):
    return confirmed_booking(verified_householder, jpeg, verifier)


@pytest.fixture
def done(confirmed, verified_householder):
    Booking.objects.filter(pk=confirmed.pk).update(status=Booking.Status.COMPLETION_PENDING)
    return jobs.confirm_done(verified_householder, confirmed.pk)


def test_a_review_is_hidden_until_both_are_in(done, verified_householder):
    mine = reviews.submit_review(verified_householder, done.pk, stars=4, comment="  Très bien  ")
    assert mine.published_at is None and mine.about == done.jobber and mine.comment == "Très bien"
    assert reviews.my_review_state(verified_householder, done.pk) == {
        "mine": {"stars": 4, "comment": "Très bien"},
        "theirs": None,
    }
    assert reviews.my_review_state(done.jobber, done.pk) == {"mine": None, "theirs": None}
    assert reviews.rating_of(done.jobber) == {"average": None, "count": 0}


def test_both_become_visible_together_with_the_same_time(done, verified_householder):
    reviews.submit_review(verified_householder, done.pk, stars=4, comment="Très bien")
    reviews.submit_review(done.jobber, done.pk, stars=5, comment="")
    first, second = Review.objects.filter(booking=done)
    assert first.published_at is not None and first.published_at == second.published_at
    assert reviews.my_review_state(done.jobber, done.pk) == {
        "mine": {"stars": 5, "comment": ""},
        "theirs": {"stars": 4, "comment": "Très bien"},
    }
    assert reviews.my_review_state(verified_householder, done.pk)["theirs"] == {"stars": 5, "comment": ""}


def test_the_window_publishes_a_lone_review(done, verified_householder, settings):
    reviews.submit_review(verified_householder, done.pk, stars=2, comment="")
    assert reviews.publish_due() == 0
    later = timezone.now() + timedelta(days=settings.REVIEW_WINDOW_DAYS, minutes=1)
    assert reviews.publish_due(later) == 1
    assert reviews.publish_due(later) == 0
    assert reviews.rating_of(done.jobber) == {"average": 2.0, "count": 1}
    from apps.bookings import tasks

    assert tasks.publish_due_reviews() == 0


def test_only_completed_bookings_by_a_party_once(done, confirmed, verified_householder, settings):
    from apps.accounts.models import User

    stranger = User.objects.create_user(username="", phone="+2250101010199", role="householder")
    assert code(lambda: reviews.submit_review(stranger, done.pk, stars=5, comment="")) == "forbidden"
    assert code(lambda: reviews.my_review_state(stranger, done.pk)) == "forbidden"
    reviews.submit_review(verified_householder, done.pk, stars=5, comment="")
    assert (
        code(lambda: reviews.submit_review(verified_householder, done.pk, stars=1, comment=""))
        == "already_reviewed"
    )
    Booking.objects.filter(pk=done.pk).update(
        completed_at=timezone.now() - timedelta(days=settings.REVIEW_WINDOW_DAYS, minutes=1)
    )
    assert code(lambda: reviews.submit_review(done.jobber, done.pk, stars=5, comment="")) == "review_closed"


@pytest.mark.parametrize("status", ["confirmed", "checked_in", "completion_pending", "disputed", "cancelled"])
def test_a_disputed_refunded_or_cancelled_booking_cannot_be_reviewed(confirmed, verified_householder, status):
    Booking.objects.filter(pk=confirmed.pk).update(status=status)
    assert (
        code(lambda: reviews.submit_review(verified_householder, confirmed.pk, stars=5, comment=""))
        == "invalid_state"
    )
    assert (
        code(lambda: reviews.submit_review(confirmed.jobber, confirmed.pk, stars=5, comment=""))
        == "invalid_state"
    )


@pytest.mark.parametrize("text", ["Appelle-moi au 07 08 09 10 11", "Écris-moi sur WhatsApp"])
def test_comment_with_contact_details_is_refused(done, verified_householder, text):
    assert (
        code(lambda: reviews.submit_review(verified_householder, done.pk, stars=5, comment=text))
        == "message_contact_details"
    )
    assert not Review.objects.exists()


def test_stars_and_length_rules(done, verified_householder, settings):
    for bad in (0, 6, None, "5", 4.5, True):
        assert (
            code(lambda b=bad: reviews.submit_review(verified_householder, done.pk, stars=b, comment=""))
            == "stars_invalid"
        )
    long = "a" * (settings.REVIEW_COMMENT_MAX + 1)
    assert (
        code(lambda: reviews.submit_review(verified_householder, done.pk, stars=5, comment=long))
        == "message_too_long"
    )
    assert reviews.submit_review(
        verified_householder, done.pk, stars=5, comment="a" * settings.REVIEW_COMMENT_MAX
    )


def test_rating_averages_published_reviews_only(done, verified_householder):
    jobber = done.jobber
    now = timezone.now()
    reviews.submit_review(verified_householder, done.pk, stars=5, comment="")
    assert reviews.rating_of(jobber)["count"] == 0
    Review.objects.filter(about=jobber).update(published_at=now)
    assert reviews.rating_of(jobber) == {"average": 5.0, "count": 1}
    assert reviews.ratings_of([jobber.pk]) == {jobber.pk: 5.0}


def test_the_applicant_card_and_trust_line_carry_the_rating(done, verified_householder, jpeg, verifier):
    reviews.submit_review(verified_householder, done.pk, stars=4, comment="")
    reviews.submit_review(done.jobber, done.pk, stars=3, comment="")
    assert applications.householder_trust(verified_householder)["rating"] == 3.0
    offer = make_offer(verified_householder, days=5)
    applications.apply(done.jobber, offer.pk, "")
    card = applications.applicants(verified_householder, offer.pk)[0]
    assert card["rating"] == 4.0
    newcomer_offer = make_offer(verified_householder, days=6)
    applications.apply(j1_jobber(jpeg, verifier), newcomer_offer.pk, "")
    assert applications.applicants(verified_householder, newcomer_offer.pk)[0]["rating"] is None
