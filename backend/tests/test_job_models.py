import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction

from apps.bookings.models import Payout, Report, Review
from tests.helpers import accepted_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def booking(verified_householder, jpeg, verifier):
    return accepted_booking(verified_householder, jpeg, verifier)


def test_one_payout_per_booking(booking):
    Payout.objects.create(booking=booking, amount_xof=3000)
    with pytest.raises(IntegrityError), transaction.atomic():
        Payout.objects.create(booking=booking, amount_xof=3000)


def test_one_open_dispute_per_booking_but_many_concerns(booking):
    def report(kind, status=Report.Status.OPEN):
        return Report.objects.create(
            booking=booking, author=booking.jobber, kind=kind, text="Souci", status=status
        )

    report(Report.Kind.DISPUTE)
    with pytest.raises(IntegrityError), transaction.atomic():
        report(Report.Kind.DISPUTE)
    report(Report.Kind.CONCERN)
    report(Report.Kind.CONCERN)
    report(Report.Kind.DISPUTE, Report.Status.RESOLVED)  # a closed one does not block


def test_one_review_per_author_and_booking(booking):
    Review.objects.create(booking=booking, author=booking.jobber, about=booking.householder, stars=5)
    with pytest.raises(IntegrityError), transaction.atomic():
        Review.objects.create(booking=booking, author=booking.jobber, about=booking.householder, stars=4)
    Review.objects.create(booking=booking, author=booking.householder, about=booking.jobber, stars=4)


@pytest.mark.parametrize("stars", [0, 6, -1])
def test_stars_are_between_one_and_five(booking, stars):
    review = Review(booking=booking, author=booking.jobber, about=booking.householder, stars=stars)
    with pytest.raises(ValidationError):
        review.full_clean()


def test_group_payment_agent_has_the_new_permissions():
    codenames = set(Group.objects.get(name="payment_agent").permissions.values_list("codename", flat=True))
    assert {"make_payout", "resolve_dispute", "view_payout", "view_report"} <= codenames


def test_a_payout_and_a_payment_know_their_amounts(booking):
    payout = Payout.objects.create(booking=booking, amount_xof=2500)
    assert payout.status == Payout.Status.DUE and payout.paid_at is None and payout.due_at
