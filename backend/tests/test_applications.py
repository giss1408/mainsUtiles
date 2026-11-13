from datetime import timedelta

import pytest
from django.utils import timezone

from apps.audit.models import AdminAction
from apps.bookings.models import Application, Booking
from apps.bookings.services import applications
from apps.bookings.services.applications import BookingError
from apps.listings.models import Offer
from tests.helpers import j1_jobber, make_offer
from tests.test_booking_models import booking_for
from tests.test_guarantor_review import new_jobber

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def offer(verified_householder):
    return make_offer(verified_householder)


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_apply_stores_the_application_and_audits(offer, jobber):
    application = applications.apply(jobber, offer.pk, "  Je suis disponible.  ")
    assert application.status == Application.Status.PENDING and application.message == "Je suis disponible."
    assert AdminAction.objects.filter(action="booking.application.apply", actor=jobber).exists()


def test_only_a_j1_jobber_can_apply(offer, jpeg, verifier):
    partial = new_jobber(jpeg, verifier)  # identity only
    assert code(lambda: applications.apply(partial, offer.pk, "")) == "jobber_verification_required"


def test_householder_and_inactive_user_forbidden(offer, jobber, verified_householder):
    assert code(lambda: applications.apply(verified_householder, offer.pk, "")) == "forbidden"
    jobber.is_active = False
    jobber.save()
    assert code(lambda: applications.apply(jobber, offer.pk, "")) == "forbidden"


@pytest.mark.parametrize("status", ["draft", "in_review", "refused", "withdrawn", "closed", "booked"])
def test_an_offer_that_is_not_published_is_unavailable(verified_householder, jobber, status):
    other = make_offer(verified_householder, status)
    assert code(lambda: applications.apply(jobber, other.pk, "")) == "offer_unavailable"


def test_a_started_offer_is_unavailable(verified_householder, jobber):
    started = make_offer(verified_householder, days=-1)
    assert code(lambda: applications.apply(jobber, started.pk, "")) == "offer_unavailable"


def test_an_unknown_offer_is_unavailable(jobber):
    assert code(lambda: applications.apply(jobber, "00000000-0000-0000-0000-000000000000", "")) == (
        "offer_unavailable"
    )


def test_second_application_to_the_same_offer_is_refused(offer, jobber):
    applications.apply(jobber, offer.pk, "")
    assert code(lambda: applications.apply(jobber, offer.pk, "")) == "already_applied"


@pytest.mark.parametrize(
    "text",
    ["07 08 09 10 11", "0708.09.10.11", "+225 0708091011", "moi@mail.ci", "écris sur WhatsApp", "whatsapp"],
)
def test_message_with_contact_details_is_refused(offer, jobber, text):
    assert code(lambda: applications.apply(jobber, offer.pk, text)) == "message_contact_details"


def test_message_length_and_empty_message(offer, jobber):
    assert code(lambda: applications.apply(jobber, offer.pk, "a" * 201)) == "message_too_long"
    assert applications.apply(jobber, offer.pk, "   ").message == ""


def test_open_applications_cap_and_offer_cap(verified_householder, jobber, settings, jpeg, verifier):
    settings.APPLICATIONS_MAX_OPEN = 2
    settings.APPLICATIONS_MAX_PER_OFFER = 1
    offers = [make_offer(verified_householder, days=2 + n) for n in range(3)]
    applications.apply(jobber, offers[0].pk, "")
    applications.apply(jobber, offers[1].pk, "")
    assert code(lambda: applications.apply(jobber, offers[2].pk, "")) == "too_many_applications"
    other = j1_jobber(jpeg, verifier)
    assert code(lambda: applications.apply(other, offers[0].pk, "")) == "offer_full"


def test_overlapping_booking_is_refused_and_a_neighbouring_one_is_not(verified_householder, jobber):
    first = make_offer(verified_householder, days=2)
    booking_for(first, Application.objects.create(offer=first, jobber=jobber))
    clash = make_offer(verified_householder, days=2, starts_at=first.starts_at + timedelta(hours=2))
    after = make_offer(verified_householder, days=2, starts_at=first.starts_at + timedelta(hours=3))
    assert code(lambda: applications.apply(jobber, clash.pk, "")) == "application_overlap"
    assert applications.apply(jobber, after.pk, "").status == Application.Status.PENDING


def test_withdraw_then_apply_again_works(offer, jobber):
    application = applications.apply(jobber, offer.pk, "")
    withdrawn = applications.withdraw(jobber, application.pk)
    assert withdrawn.status == Application.Status.WITHDRAWN and withdrawn.decided_at
    assert AdminAction.objects.filter(action="booking.application.withdraw").exists()
    assert applications.apply(jobber, offer.pk, "").status == Application.Status.PENDING


def test_withdraw_only_pending_and_only_own(offer, jobber, jpeg, verifier):
    application = applications.apply(jobber, offer.pk, "")
    other = j1_jobber(jpeg, verifier)
    assert code(lambda: applications.withdraw(other, application.pk)) == "forbidden"
    applications.withdraw(jobber, application.pk)
    assert code(lambda: applications.withdraw(jobber, application.pk)) == "invalid_state"
    assert code(lambda: applications.withdraw(jobber, "not-a-uuid")) == "forbidden"


def test_a_jobber_with_a_dispute_cannot_apply(verified_householder, offer, jobber):
    old = make_offer(verified_householder, days=1, status=Offer.Status.CLOSED)
    booking_for(old, Application.objects.create(offer=old, jobber=jobber), Booking.Status.DISPUTED)
    assert code(lambda: applications.apply(jobber, offer.pk, "")) == "dispute_open"


def test_my_applications_lists_newest_first(verified_householder, jobber):
    one = make_offer(verified_householder, days=2)
    two = make_offer(verified_householder, days=3)
    first = applications.apply(jobber, one.pk, "")
    second = applications.apply(jobber, two.pk, "")
    assert list(applications.my_applications(jobber)) == [second, first]
    assert timezone.now() >= first.created_at
