from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking
from apps.bookings.services import jobs, payments
from apps.bookings.services.errors import BookingError
from tests.helpers import paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]

HOME = (5.3599, -3.9871)


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


def test_check_in_moves_the_booking_and_records_the_distance(confirmed):
    start_in(confirmed, minutes=10)
    booking = jobs.check_in(confirmed.jobber, confirmed.pk, lat=5.3600, lng=-3.9872, accuracy_m=12)
    assert booking.status == Booking.Status.CHECKED_IN and booking.checked_in_at
    assert 0 < booking.checkin_distance_m < 30
    assert not jobs.needs_a_look(booking)
    assert AdminAction.objects.filter(action="booking.check_in", actor=confirmed.jobber).exists()


def test_check_in_without_a_position_still_works_and_records_no_distance(confirmed):
    start_in(confirmed, minutes=10)
    booking = jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)
    assert booking.status == Booking.Status.CHECKED_IN and booking.checkin_distance_m is None
    assert not jobs.needs_a_look(booking)


def test_too_early_and_too_late_have_their_codes(confirmed, settings):
    start_in(confirmed, minutes=settings.CHECKIN_EARLY_MINUTES + 5)
    assert (
        code(lambda: jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)) == "checkin_too_early"
    )
    start_in(confirmed, hours=-4)  # a 3 hour job that began 4 hours ago
    assert code(lambda: jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)) == "checkin_closed"


def test_only_the_booked_jobber_of_a_confirmed_booking_can_check_in(
    confirmed, verified_householder, jpeg, verifier
):
    start_in(confirmed, minutes=5)
    assert code(lambda: jobs.check_in(verified_householder, confirmed.pk, lat=None, lng=None)) == "forbidden"
    assert code(lambda: jobs.check_in(confirmed.jobber, "not-a-uuid", lat=None, lng=None)) == "forbidden"
    from tests.helpers import accepted_booking

    unpaid = accepted_booking(verified_householder, jpeg, verifier, days=3)
    start_in(unpaid, minutes=5)
    assert code(lambda: jobs.check_in(unpaid.jobber, unpaid.pk, lat=None, lng=None)) == "invalid_state"


def test_a_far_check_in_is_flagged_for_staff(confirmed):
    start_in(confirmed, minutes=5)
    booking = jobs.check_in(confirmed.jobber, confirmed.pk, lat=5.40, lng=-3.99)
    assert booking.checkin_distance_m > 4000 and jobs.needs_a_look(booking)


def test_check_out_needs_a_check_in_and_sets_the_wait(confirmed):
    start_in(confirmed, minutes=5)
    assert code(lambda: jobs.check_out(confirmed.jobber, confirmed.pk)) == "invalid_state"
    jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)
    booking = jobs.check_out(confirmed.jobber, confirmed.pk)
    assert booking.status == Booking.Status.COMPLETION_PENDING and booking.checked_out_at
    assert AdminAction.objects.filter(action="booking.check_out", actor=confirmed.jobber).exists()
    assert code(lambda: jobs.check_out(confirmed.jobber, confirmed.pk)) == "invalid_state"


def test_distance_is_in_metres():
    metres = jobs.distance_m(HOME, (5.3689, -3.9871))
    assert abs(metres - 1001) <= 5
    assert jobs.distance_m(HOME, HOME) == 0


def test_double_tap_check_in_is_invalid_state(confirmed):
    start_in(confirmed, minutes=5)
    jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)
    assert code(lambda: jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)) == "invalid_state"


def test_a_bad_position_is_ignored_not_trusted(confirmed):
    start_in(confirmed, minutes=5)
    booking = jobs.check_in(confirmed.jobber, confirmed.pk, lat=999, lng=-3.9871)
    assert booking.status == Booking.Status.CHECKED_IN and booking.checkin_distance_m is None
