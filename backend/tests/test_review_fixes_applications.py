"""Regressions found by the review of the applications stage."""

from datetime import timedelta

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from apps.bookings.api.serializers import ApplyBodySerializer
from apps.bookings.models import Application, Booking
from apps.bookings.services import applications
from apps.bookings.services.applications import BookingError
from apps.listings.models import Offer
from apps.listings.services import offers as offer_service
from apps.verification.models import IdentityVerification
from tests.helpers import j1_jobber, make_offer
from tests.test_booking_models import booking_for
from tests.test_offers_api import bearer_for_user

pytestmark = pytest.mark.django_db


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_accept_refuses_a_jobber_who_became_busy_after_applying(verified_householder, jobber):
    first = make_offer(verified_householder, days=2)
    second = make_offer(verified_householder, days=2, starts_at=first.starts_at + timedelta(hours=1))
    a = applications.apply(jobber, first.pk, "")
    b = applications.apply(jobber, second.pk, "")
    applications.accept(verified_householder, a.pk)
    assert code(lambda: applications.accept(verified_householder, b.pk)) == "application_overlap"
    second.refresh_from_db()
    assert second.status == Offer.Status.PUBLISHED and not Booking.objects.filter(offer=second).exists()


def test_accept_refuses_a_jobber_who_opened_a_dispute_after_applying(verified_householder, jobber):
    offer = make_offer(verified_householder, days=3)
    application = applications.apply(jobber, offer.pk, "")
    old = make_offer(verified_householder, days=-5, status=Offer.Status.CLOSED)
    booking_for(old, Application.objects.create(offer=old, jobber=jobber), Booking.Status.DISPUTED)
    assert code(lambda: applications.accept(verified_householder, application.pk)) == "dispute_open"


def test_withdrawing_a_booked_offer_cancels_its_unpaid_booking(verified_householder, jobber):
    offer = make_offer(verified_householder)
    booking = applications.accept(verified_householder, applications.apply(jobber, offer.pk, "").pk)
    offer_service.withdraw(offer, user=verified_householder)
    offer.refresh_from_db()
    booking.refresh_from_db()
    assert offer.status == Offer.Status.WITHDRAWN and booking.status == Booking.Status.CANCELLED
    # The jobber is free again, and the offer's slot too.
    other = make_offer(verified_householder, days=2)
    assert applications.apply(jobber, other.pk, "").status == Application.Status.PENDING


def test_a_booking_that_moved_on_blocks_the_withdrawal(verified_householder, jobber):
    offer = make_offer(verified_householder)
    booking = applications.accept(verified_householder, applications.apply(jobber, offer.pk, "").pk)
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.CONFIRMED)
    with pytest.raises(offer_service.OfferError) as caught:
        offer_service.withdraw(offer, user=verified_householder)
    assert caught.value.code == "invalid_state"


def test_tidy_closes_a_booked_offer_that_was_never_paid_and_started(verified_householder, jobber):
    offer = make_offer(verified_householder)
    booking = applications.accept(verified_householder, applications.apply(jobber, offer.pk, "").pk)
    Offer.objects.filter(pk=offer.pk).update(starts_at=timezone.now() - timedelta(minutes=1))
    offer_service.tidy()
    offer.refresh_from_db()
    booking.refresh_from_db()
    assert offer.status == Offer.Status.CLOSED and booking.status == Booking.Status.EXPIRED


def test_tidy_leaves_a_paid_booking_alone(verified_householder, jobber):
    offer = make_offer(verified_householder)
    booking = applications.accept(verified_householder, applications.apply(jobber, offer.pk, "").pk)
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.CONFIRMED)
    Offer.objects.filter(pk=offer.pk).update(starts_at=timezone.now() - timedelta(minutes=1))
    offer_service.tidy()
    offer.refresh_from_db()
    assert offer.status == Offer.Status.BOOKED


def test_close_stale_keeps_applications_of_offers_still_in_review(verified_householder, jobber):
    offer = make_offer(verified_householder, status=Offer.Status.PUBLISHED)
    application = applications.apply(jobber, offer.pk, "")
    Offer.objects.filter(pk=offer.pk).update(status=Offer.Status.IN_REVIEW)
    assert applications.close_stale() == 0
    application.refresh_from_db()
    assert application.status == Application.Status.PENDING
    Offer.objects.filter(pk=offer.pk).update(status=Offer.Status.REFUSED)
    assert applications.close_stale() == 1


def _queries(call) -> int:
    with CaptureQueriesContext(connection) as ctx:
        call()
    return len(ctx)


def test_applicants_cost_the_same_for_one_or_five(verified_householder, jpeg, verifier):
    one = make_offer(verified_householder, days=2)
    many = make_offer(verified_householder, days=3)
    applications.apply(j1_jobber(jpeg, verifier), one.pk, "")
    for _ in range(5):
        applications.apply(j1_jobber(jpeg, verifier), many.pk, "")
    single = _queries(lambda: applications.applicants(verified_householder, one.pk))
    five = _queries(lambda: applications.applicants(verified_householder, many.pk))
    assert five == single


def test_my_offers_cost_does_not_grow_with_the_number_of_offers(
    api_client, verified_householder, jpeg, verifier
):
    def get():
        return api_client.get("/api/v1/my-offers", HTTP_AUTHORIZATION=bearer_for_user(verified_householder))

    make_offer(verified_householder, days=2)
    get()  # warm the device and token setup
    one = _queries(get)
    for n in range(3, 6):
        offer = make_offer(verified_householder, days=n)
        applications.apply(j1_jobber(jpeg, verifier), offer.pk, "")
    assert _queries(get) <= one + 1


def test_applicants_without_a_confirmed_identity_are_not_listed_and_cannot_be_accepted(
    verified_householder, jobber
):
    offer = make_offer(verified_householder)
    application = applications.apply(jobber, offer.pk, "")
    IdentityVerification.objects.filter(user=jobber).update(status="expired")
    assert applications.applicants(verified_householder, offer.pk) == []
    assert code(lambda: applications.accept(verified_householder, application.pk)) == (
        "applicant_not_verified"
    )


def test_accepting_through_the_wrong_offer_is_a_404_with_the_error_shape(
    api_client, verified_householder, jobber
):
    offer = make_offer(verified_householder)
    other = make_offer(verified_householder, days=3)
    application = applications.apply(jobber, offer.pk, "")
    response = api_client.post(
        f"/api/v1/my-offers/{other.pk}/applicants/{application.pk}/accept",
        HTTP_AUTHORIZATION=bearer_for_user(verified_householder),
    )
    assert response.status_code == 404 and response.json()["error"] == "not_found"
    missing = api_client.post(
        f"/api/v1/my-offers/{offer.pk}/applicants/00000000-0000-0000-0000-000000000000/accept",
        HTTP_AUTHORIZATION=bearer_for_user(verified_householder),
    )
    assert missing.status_code == 404 and missing.json()["error"] == "not_found"


def test_the_apply_schema_does_not_advertise_a_limit_the_service_does_not_have():
    assert ApplyBodySerializer().fields["message"].max_length is None
