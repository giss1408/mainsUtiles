from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment, Payout, Report
from apps.bookings.services import jobs, payments, payouts, reports
from apps.bookings.services.errors import BookingError
from tests.helpers import confirmed_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


@pytest.fixture
def agent():
    user = User.objects.create_user(username="judge", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def outsider():
    return User.objects.create_user(username="nobody", password="pw", role="staff", is_staff=True)


@pytest.fixture
def working(verified_householder, jpeg, verifier):
    """A booking whose jobber has checked in."""
    booking = confirmed_booking(verified_householder, jpeg, verifier)
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    return jobs.check_in(booking.jobber, booking.pk, lat=None, lng=None)


@pytest.fixture
def disputed(working, verified_householder):
    report = reports.report_problem(
        verified_householder, working.pk, text="Le travail n'est pas fait", dispute=True
    )
    working.refresh_from_db()
    return report


def test_a_dispute_freezes_the_booking_and_the_payout(working, verified_householder):
    report = reports.report_problem(
        verified_householder, working.pk, text="  Rien n'a été fait  ", dispute=True
    )
    working.refresh_from_db()
    assert report.kind == Report.Kind.DISPUTE and report.text == "Rien n'a été fait"
    assert working.status == Booking.Status.DISPUTED
    assert code(lambda: jobs.check_out(working.jobber, working.pk)) == "invalid_state"
    assert code(lambda: jobs.confirm_done(verified_householder, working.pk)) == "invalid_state"
    assert jobs.complete_overdue(timezone.now() + timedelta(days=30)) == 0
    assert not Payout.objects.filter(booking=working).exists()
    action = AdminAction.objects.get(action="booking.report")
    assert action.actor == verified_householder and "Rien" not in str(action.__dict__)


def test_only_a_party_can_report_and_a_stranger_gets_forbidden(working, outsider):
    other = User.objects.create_user(username="", phone="+2250101010199", role="householder")
    for stranger in (other, outsider, None):
        assert (
            code(lambda u=stranger: reports.report_problem(u, working.pk, text="Bonjour", dispute=False))
            == "forbidden"
        )
    assert (
        code(lambda: reports.report_problem(working.jobber, "not-a-uuid", text="Bonjour", dispute=False))
        == "forbidden"
    )
    assert (
        reports.report_problem(working.jobber, working.pk, text="Bonjour", dispute=False).author
        == working.jobber
    )


def test_a_dispute_after_completion_is_refused_but_a_concern_is_kept(working, verified_householder, settings):
    jobs.check_out(working.jobber, working.pk)
    jobs.confirm_done(verified_householder, working.pk)
    assert (
        code(lambda: reports.report_problem(verified_householder, working.pk, text="Trop tard", dispute=True))
        == "invalid_state"
    )
    kept = reports.report_problem(verified_householder, working.pk, text="Une remarque", dispute=False)
    assert kept.kind == Report.Kind.CONCERN
    Booking.objects.filter(pk=working.pk).update(
        completed_at=timezone.now() - timedelta(days=settings.REVIEW_WINDOW_DAYS, minutes=1)
    )
    assert (
        code(lambda: reports.report_problem(verified_householder, working.pk, text="Encore", dispute=False))
        == "invalid_state"
    )


def test_a_report_before_check_in_is_refused(verified_householder, jpeg, verifier):
    booking = confirmed_booking(verified_householder, jpeg, verifier)
    for dispute in (True, False):
        assert (
            code(
                lambda d=dispute: reports.report_problem(
                    verified_householder, booking.pk, text="Trop tôt", dispute=d
                )
            )
            == "invalid_state"
        )


def test_a_second_dispute_becomes_a_concern(disputed, working):
    second = reports.report_problem(working.jobber, working.pk, text="Ce n'est pas vrai", dispute=True)
    assert second.kind == Report.Kind.CONCERN
    assert Report.objects.filter(booking=working, kind=Report.Kind.DISPUTE).count() == 1


def test_a_concern_does_not_change_the_booking(working):
    reports.report_problem(working.jobber, working.pk, text="Le chien n'était pas attaché", dispute=False)
    working.refresh_from_db()
    assert working.status == Booking.Status.CHECKED_IN


def test_release_pays_the_jobber_in_full(disputed, working, agent):
    reports.resolve_dispute(disputed, staff=agent, outcome="release", note="Photos à l'appui")
    working.refresh_from_db()
    assert working.status == Booking.Status.COMPLETED and working.completion == "staff"
    assert working.payout.amount_xof == working.pay_xof
    assert Payment.objects.get(booking=working).status == Payment.Status.CONFIRMED
    assert disputed.status == Report.Status.RESOLVED and disputed.outcome == "release"
    assert disputed.resolved_by == agent and disputed.note == "Photos à l'appui"
    assert AdminAction.objects.filter(action="booking.dispute.resolve", actor=agent).exists()


def test_refund_cancels_and_asks_for_a_refund(disputed, working, agent):
    reports.resolve_dispute(disputed, staff=agent, outcome="refund", note="Le jobber est parti")
    working.refresh_from_db()
    payment = Payment.objects.get(booking=working)
    assert working.status == Booking.Status.CANCELLED
    assert payment.status == Payment.Status.REFUND_DUE and payment.refund_xof is None
    assert payments.refund_amount(payment) == payment.amount_xof
    assert not Payout.objects.filter(booking=working).exists()


def test_split_pays_part_and_refunds_the_rest(disputed, working, agent):
    reports.resolve_dispute(disputed, staff=agent, outcome="split", note="Moitié faite", jobber_xof=1000)
    working.refresh_from_db()
    payment = Payment.objects.get(booking=working)
    assert working.status == Booking.Status.COMPLETED and working.payout.amount_xof == 1000
    assert payment.status == Payment.Status.REFUND_DUE and payment.refund_xof == working.pay_xof - 1000
    assert payments.refund_amount(payment) == working.pay_xof - 1000
    assert disputed.jobber_xof == 1000
    # The jobber's share is still paid, before or after the refund is sent.
    payments.record_refund(payment, staff=agent, reference="RMB-12345")
    payouts.record_payout(working.payout, staff=agent, reference="MOMO-998877")
    assert Payout.objects.get(booking=working).status == Payout.Status.PAID


def test_split_amounts_are_validated(disputed, working, agent):
    for bad in (None, 0, -5, working.pay_xof, working.pay_xof + 1, "1000", 10.5, True):
        assert (
            code(
                lambda b=bad: reports.resolve_dispute(
                    disputed, staff=agent, outcome="split", note="x", jobber_xof=b
                )
            )
            == "split_invalid"
        )
    working.refresh_from_db()
    assert working.status == Booking.Status.DISPUTED


def test_resolving_needs_the_permission_a_note_and_an_open_dispute(disputed, working, agent, outsider):
    assert (
        code(lambda: reports.resolve_dispute(disputed, staff=outsider, outcome="release", note="x"))
        == "forbidden"
    )
    assert (
        code(lambda: reports.resolve_dispute(disputed, staff=agent, outcome="release", note="  "))
        == "reason_required"
    )
    assert (
        code(lambda: reports.resolve_dispute(disputed, staff=agent, outcome="burn", note="x"))
        == "outcome_invalid"
    )
    concern = reports.report_problem(working.jobber, working.pk, text="Une remarque", dispute=False)
    assert (
        code(lambda: reports.resolve_dispute(concern, staff=agent, outcome="release", note="x"))
        == "invalid_state"
    )
    reports.resolve_dispute(disputed, staff=agent, outcome="release", note="x")
    assert (
        code(lambda: reports.resolve_dispute(disputed, staff=agent, outcome="refund", note="x"))
        == "invalid_state"
    )
    assert Payout.objects.filter(booking=working).count() == 1


@pytest.mark.parametrize("bad", ["", "  ", "ab", "x" * 501, None])
def test_text_rules(working, bad):
    assert (
        code(lambda: reports.report_problem(working.jobber, working.pk, text=bad, dispute=False))
        == "report_invalid"
    )
