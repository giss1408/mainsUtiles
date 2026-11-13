from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking
from apps.bookings.services import bookings, payments
from apps.bookings.services.errors import BookingError
from apps.verification.models import IdentityVerification
from apps.verification.services.submissions import read_photo_bytes
from tests.helpers import accepted_booking, paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def confirmed(verified_householder, jpeg, verifier, cashier):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    booking.refresh_from_db()
    return booking


def start_in(booking, **delta):
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(**delta))
    booking.refresh_from_db()


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_address_is_refused_before_the_window_and_after_the_job(confirmed, settings):
    start_in(confirmed, hours=settings.ADDRESS_RELEASE_HOURS + 1)
    assert code(lambda: bookings.address_for(confirmed.jobber, confirmed.pk)) == "address_not_yet"
    start_in(confirmed, hours=-4)  # a 3 hour job that began 4 hours ago
    assert code(lambda: bookings.address_for(confirmed.jobber, confirmed.pk)) == "address_closed"


def test_address_is_released_to_the_booked_jobber_only_and_audited_each_time(
    confirmed, verified_householder, settings
):
    start_in(confirmed, hours=settings.ADDRESS_RELEASE_HOURS - 1)
    assert code(lambda: bookings.address_for(verified_householder, confirmed.pk)) == "forbidden"
    first = bookings.address_for(confirmed.jobber, confirmed.pk)
    bookings.address_for(confirmed.jobber, confirmed.pk)
    confirmed.refresh_from_db()
    assert confirmed.status == Booking.Status.ADDRESS_RELEASED
    assert AdminAction.objects.filter(action="booking.address.release", actor=confirmed.jobber).count() == 2
    assert set(first) == {"latitude", "longitude", "commune", "quartier"}


def test_the_pin_comes_from_the_confirmed_home_location(confirmed, settings):
    start_in(confirmed, hours=1)
    pin = bookings.address_for(confirmed.jobber, confirmed.pk)
    assert (pin["latitude"], pin["longitude"]) == (5.3599, -3.9871)
    assert (pin["commune"], pin["quartier"]) == ("Cocody", "Angré")


def test_address_needs_a_confirmed_booking(verified_householder, jpeg, verifier):
    accepted = accepted_booking(verified_householder, jpeg, verifier)
    start_in(accepted, hours=1)
    assert code(lambda: bookings.address_for(accepted.jobber, accepted.pk)) == "invalid_state"
    review, _ = paid_booking(verified_householder, jpeg, verifier, days=3, seed=9, reference="WAVE-555555")
    start_in(review, hours=1)
    assert code(lambda: bookings.address_for(review.jobber, review.pk)) == "invalid_state"


def test_a_cancelled_booking_no_longer_releases_the_address(confirmed, verified_householder):
    start_in(confirmed, hours=1)
    bookings.cancel(verified_householder, confirmed.pk)
    assert code(lambda: bookings.address_for(confirmed.jobber, confirmed.pk)) == "invalid_state"


def test_available_from_is_the_opening_of_the_window(confirmed, settings):
    assert bookings.available_from(confirmed) == confirmed.starts_at - timedelta(
        hours=settings.ADDRESS_RELEASE_HOURS
    )


def test_jobber_card_needs_a_confirmed_booking_and_is_for_the_householder_only(
    confirmed, verified_householder, jpeg, verifier
):
    accepted = accepted_booking(verified_householder, jpeg, verifier, days=3)
    assert code(lambda: bookings.jobber_card(verified_householder, accepted.pk)) == "invalid_state"
    assert code(lambda: bookings.jobber_card(confirmed.jobber, confirmed.pk)) == "forbidden"
    card = bookings.jobber_card(verified_householder, confirmed.pk)
    assert card == {"full_name": "Jeune Jobber", "has_photo": True}
    assert AdminAction.objects.filter(action="booking.jobber.view", actor=verified_householder).exists()
    bookings.cancel(verified_householder, confirmed.pk)
    assert code(lambda: bookings.jobber_card(verified_householder, confirmed.pk)) == "invalid_state"


def test_jobber_photo_is_the_confirmed_selfie_and_audited(confirmed, verified_householder):
    data = bookings.jobber_photo(verified_householder, confirmed.pk)
    selfie = IdentityVerification.objects.get(user=confirmed.jobber).selfie
    assert data == read_photo_bytes(selfie)
    assert AdminAction.objects.filter(action="booking.jobber.view_photo", actor=verified_householder).exists()
    assert code(lambda: bookings.jobber_photo(confirmed.jobber, confirmed.pk)) == "forbidden"


def test_nothing_before_payment_contains_the_jobbers_name_or_the_pin(verified_householder, jpeg, verifier):
    accepted = accepted_booking(verified_householder, jpeg, verifier)
    start_in(accepted, hours=1)
    for call in (
        lambda: bookings.jobber_card(verified_householder, accepted.pk),
        lambda: bookings.jobber_photo(verified_householder, accepted.pk),
        lambda: bookings.address_for(accepted.jobber, accepted.pk),
    ):
        assert code(call) == "invalid_state"
