from datetime import timedelta

import pytest
from django.utils import timezone

from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment, Payout, Report
from apps.bookings.services import jobs
from apps.bookings.services.errors import BookingError
from apps.listings.models import Offer
from tests.helpers import confirmed_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def confirmed(verified_householder, jpeg, verifier):
    return confirmed_booking(verified_householder, jpeg, verifier)


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def finished(booking):
    """The jobber arrived and left: the booking waits for the householder."""
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    jobs.check_in(booking.jobber, booking.pk, lat=None, lng=None)
    return jobs.check_out(booking.jobber, booking.pk)


def test_confirm_completes_the_booking_and_creates_one_payout(confirmed, verified_householder):
    pending = finished(confirmed)
    done = jobs.confirm_done(verified_householder, pending.pk)
    assert done.status == Booking.Status.COMPLETED and done.completed_at and done.completion == "householder"
    payout = Payout.objects.get(booking=done)
    assert payout.status == Payout.Status.DUE and payout.amount_xof == done.pay_xof
    assert AdminAction.objects.filter(action="booking.complete", actor=verified_householder).exists()


def test_only_the_householder_can_confirm_and_only_while_pending(confirmed, verified_householder):
    assert code(lambda: jobs.confirm_done(verified_householder, confirmed.pk)) == "invalid_state"
    pending = finished(confirmed)
    assert code(lambda: jobs.confirm_done(pending.jobber, pending.pk)) == "forbidden"
    assert code(lambda: jobs.confirm_done(verified_householder, "not-a-uuid")) == "forbidden"


def test_confirming_twice_makes_one_payout(confirmed, verified_householder):
    pending = finished(confirmed)
    jobs.confirm_done(verified_householder, pending.pk)
    assert code(lambda: jobs.confirm_done(verified_householder, pending.pk)) == "invalid_state"
    assert Payout.objects.count() == 1


def test_timeout_completes_by_itself_and_audits_the_system(confirmed, settings):
    pending = finished(confirmed)
    Booking.objects.filter(pk=pending.pk).update(
        checked_out_at=timezone.now() - timedelta(hours=settings.RELEASE_TIMEOUT_HOURS, minutes=1)
    )
    assert jobs.complete_overdue() == 1
    pending.refresh_from_db()
    assert pending.status == Booking.Status.COMPLETED and pending.completion == "timeout"
    assert Payout.objects.filter(booking=pending, status="due").count() == 1
    assert AdminAction.objects.filter(action="booking.complete", actor__isnull=True).exists()
    assert jobs.complete_overdue() == 0


def test_a_booking_just_inside_the_timeout_is_left_alone(confirmed, settings):
    pending = finished(confirmed)
    Booking.objects.filter(pk=pending.pk).update(
        checked_out_at=timezone.now() - timedelta(hours=settings.RELEASE_TIMEOUT_HOURS - 1)
    )
    assert jobs.complete_overdue() == 0
    pending.refresh_from_db()
    assert pending.status == Booking.Status.COMPLETION_PENDING and not Payout.objects.exists()


def test_a_paid_booking_nobody_attended_is_cancelled_and_refunded(confirmed):
    Booking.objects.filter(pk=confirmed.pk).update(starts_at=timezone.now() - timedelta(hours=4))
    assert jobs.close_no_shows() == 1
    confirmed.refresh_from_db()
    assert confirmed.status == Booking.Status.CANCELLED and confirmed.cancel_reason == "no_show"
    assert Payment.objects.get(booking=confirmed).status == Payment.Status.REFUND_DUE
    assert Offer.objects.get(pk=confirmed.offer_id).status == Offer.Status.CLOSED
    assert not Payout.objects.exists()
    assert jobs.close_no_shows() == 0


def test_an_attended_booking_is_never_a_no_show(confirmed):
    pending = finished(confirmed)
    Booking.objects.filter(pk=pending.pk).update(starts_at=timezone.now() - timedelta(hours=8))
    assert jobs.close_no_shows() == 0
    pending.refresh_from_db()
    assert pending.status == Booking.Status.COMPLETION_PENDING


def test_a_booking_still_in_its_time_is_not_a_no_show(confirmed):
    assert jobs.close_no_shows() == 0
    Booking.objects.filter(pk=confirmed.pk).update(starts_at=timezone.now() - timedelta(hours=1))
    assert jobs.close_no_shows() == 0


def test_a_jobber_who_never_checks_out_ends_in_a_dispute_not_a_payout(confirmed, settings):
    Booking.objects.filter(pk=confirmed.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    jobs.check_in(confirmed.jobber, confirmed.pk, lat=None, lng=None)
    Booking.objects.filter(pk=confirmed.pk).update(
        starts_at=timezone.now() - timedelta(hours=3 + settings.CHECKOUT_GRACE_HOURS, minutes=1)
    )
    assert jobs.flag_unclosed() == 1
    confirmed.refresh_from_db()
    assert confirmed.status == Booking.Status.DISPUTED
    report = Report.objects.get(booking=confirmed)
    assert report.kind == Report.Kind.DISPUTE and report.status == Report.Status.OPEN
    assert report.author == confirmed.jobber and "départ" in report.text
    assert not Payout.objects.exists()
    assert jobs.flag_unclosed() == 0


def test_the_sweep_tasks_run():
    from apps.bookings import tasks

    assert tasks.complete_overdue_bookings() == 0
    assert tasks.close_no_show_bookings() == 0
    assert tasks.flag_unclosed_bookings() == 0
