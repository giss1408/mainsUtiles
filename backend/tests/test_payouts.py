import pytest
from django.contrib.auth.models import Group
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment, Payout
from apps.bookings.services import jobs, payouts
from apps.bookings.services.errors import BookingError
from apps.verification.services.encryption import decrypt_text
from tests.helpers import confirmed_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


@pytest.fixture
def agent():
    user = User.objects.create_user(username="payer", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def outsider():
    return User.objects.create_user(username="nobody", password="pw", role="staff", is_staff=True)


def completed(householder, jpeg, verifier, *, days=2, seed=7, reference="WAVE-123456"):
    booking = confirmed_booking(householder, jpeg, verifier, days=days, seed=seed, reference=reference)
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.COMPLETION_PENDING)
    return jobs.confirm_done(householder, booking.pk).payout


@pytest.fixture
def payout(verified_householder, jpeg, verifier):
    return completed(verified_householder, jpeg, verifier)


def test_queue_lists_due_payouts_oldest_first(payout, agent):
    assert list(payouts.payout_queue(staff=agent)) == [payout]
    payouts.record_payout(payout, staff=agent, reference="MOMO-998877")
    assert list(payouts.payout_queue(staff=agent)) == []


def test_details_show_the_phone_only_to_the_right_holder_and_audit(payout, agent, outsider):
    assert code(lambda: payouts.payout_details(payout, staff=outsider)) == "forbidden"
    assert not AdminAction.objects.filter(action="booking.payout.view").exists()
    data = payouts.payout_details(payout, staff=agent)
    assert data["jobber_phone"] == payout.booking.jobber.phone
    assert data["amount_xof"] == payout.amount_xof
    assert data["category_name"] == payout.booking.category_name
    assert AdminAction.objects.filter(action="booking.payout.view", actor=agent).exists()


def test_record_payout_stores_an_encrypted_reference_once(payout, agent):
    payouts.record_payout(payout, staff=agent, reference="  MOMO-998877 ")
    payout.refresh_from_db()
    assert payout.status == Payout.Status.PAID and payout.paid_by == agent and payout.paid_at
    assert "MOMO-998877" not in payout.reference
    assert decrypt_text(payout.reference) == "MOMO-998877"
    assert AdminAction.objects.filter(action="booking.payout.pay", actor=agent).exists()


def test_a_refunded_booking_is_never_paid(payout, agent):
    Payment.objects.filter(booking=payout.booking).update(status=Payment.Status.REFUND_DUE)
    assert (
        code(lambda: payouts.record_payout(payout, staff=agent, reference="MOMO-998877")) == "invalid_state"
    )
    Payment.objects.filter(booking=payout.booking).update(status=Payment.Status.REFUNDED)
    assert (
        code(lambda: payouts.record_payout(payout, staff=agent, reference="MOMO-998877")) == "invalid_state"
    )
    payout.refresh_from_db()
    assert payout.status == Payout.Status.DUE


@pytest.mark.parametrize("bad", ["", "   ", "abc", "x" * 41, "REF#1234", "réf-1234"])
def test_reference_rules(payout, agent, bad):
    assert code(lambda: payouts.record_payout(payout, staff=agent, reference=bad)) == "reference_invalid"
    payout.refresh_from_db()
    assert payout.status == Payout.Status.DUE


def test_without_the_permission_nothing_works(payout, outsider):
    assert code(lambda: payouts.payout_queue(staff=outsider)) == "forbidden"
    assert code(lambda: payouts.payout_details(payout, staff=outsider)) == "forbidden"
    assert code(lambda: payouts.record_payout(payout, staff=outsider, reference="MOMO-998877")) == "forbidden"
    assert code(lambda: payouts.payout_queue(staff=None)) == "forbidden"


def test_double_payout_is_invalid_state(payout, agent):
    payouts.record_payout(payout, staff=agent, reference="MOMO-998877")
    assert (
        code(lambda: payouts.record_payout(payout, staff=agent, reference="MOMO-112233")) == "invalid_state"
    )
    payout.refresh_from_db()
    assert decrypt_text(payout.reference) == "MOMO-998877"
