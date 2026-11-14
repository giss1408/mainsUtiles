import pytest
from django.contrib.auth.models import Group

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment
from apps.bookings.services import payments
from apps.bookings.services.applications import BookingError
from tests.helpers import paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def paid(verified_householder, jpeg, verifier):
    return paid_booking(verified_householder, jpeg, verifier)


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_confirm_makes_the_booking_confirmed_and_audits(paid, cashier):
    booking, payment = paid
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    payment.refresh_from_db()
    booking.refresh_from_db()
    assert payment.status == Payment.Status.CONFIRMED and booking.status == Booking.Status.CONFIRMED
    assert payment.decided_by == cashier and payment.decided_at
    assert AdminAction.objects.filter(action="booking.payment.confirm", actor=cashier).exists()


def test_both_checks_are_required(paid, cashier):
    _, payment = paid
    for amount, reference in ((True, False), (False, True), (False, False)):
        assert (
            code(
                lambda a=amount, r=reference: payments.confirm_payment(
                    payment, staff=cashier, amount_matches=a, reference_matches=r
                )
            )
            == "checks_required"
        )
    payment.refresh_from_db()
    assert payment.status == Payment.Status.SUBMITTED


def test_the_same_reference_cannot_confirm_a_second_booking(
    paid, cashier, verified_householder, jpeg, verifier
):
    _, first = paid
    payments.confirm_payment(first, staff=cashier, amount_matches=True, reference_matches=True)
    other, second = paid_booking(
        verified_householder, jpeg, verifier, reference="wave 123 456", days=3, seed=9
    )
    assert (
        code(
            lambda: payments.confirm_payment(
                second, staff=cashier, amount_matches=True, reference_matches=True
            )
        )
        == "reference_used"
    )
    second.refresh_from_db()
    other.refresh_from_db()
    assert second.status == Payment.Status.SUBMITTED and other.status == Booking.Status.PAYMENT_REVIEW


def test_refuse_returns_the_booking_to_accepted_with_the_reason(paid, cashier):
    booking, payment = paid
    payments.refuse_payment(payment, staff=cashier, reason="Montant reçu : 2 000 FCFA")
    payment.refresh_from_db()
    booking.refresh_from_db()
    assert payment.status == Payment.Status.REFUSED and payment.reason == "Montant reçu : 2 000 FCFA"
    assert booking.status == Booking.Status.ACCEPTED
    assert AdminAction.objects.filter(action="booking.payment.refuse", actor=cashier).exists()
    assert code(lambda: payments.refuse_payment(payment, staff=cashier, reason="")) == "invalid_state"


def test_a_reason_is_required_to_refuse(paid, cashier):
    _, payment = paid
    assert code(lambda: payments.refuse_payment(payment, staff=cashier, reason="  ")) == "reason_required"


def test_a_decided_payment_cannot_be_decided_again(paid, cashier):
    _, payment = paid
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    stale = Payment.objects.get(pk=payment.pk)
    stale.status = Payment.Status.SUBMITTED  # a copy read before the first decision
    assert (
        code(
            lambda: payments.confirm_payment(
                stale, staff=cashier, amount_matches=True, reference_matches=True
            )
        )
        == "invalid_state"
    )
    assert code(lambda: payments.refuse_payment(stale, staff=cashier, reason="non")) == "invalid_state"


def test_without_the_permission_nothing_works(paid, staff_user, verified_householder):
    _, payment = paid
    for staff in (staff_user, verified_householder, None):
        assert (
            code(
                lambda s=staff: payments.confirm_payment(
                    payment, staff=s, amount_matches=True, reference_matches=True
                )
            )
            == "forbidden"
        )
        assert code(lambda s=staff: payments.refuse_payment(payment, staff=s, reason="x")) == "forbidden"
        assert code(lambda s=staff: payments.read_proof(payment, staff=s)) == "forbidden"


def test_every_proof_view_is_audited(paid, cashier, jpeg):
    _, payment = paid
    assert payments.read_proof(payment, staff=cashier) == jpeg(7, size=333)
    assert AdminAction.objects.filter(action="booking.payment.view_proof", actor=cashier).count() == 1


def test_proof_seen_before_flags_the_same_image_on_two_bookings(paid, verified_householder, jpeg, verifier):
    _, first = paid
    assert not payments.proof_seen_before(first)
    _, second = paid_booking(verified_householder, jpeg, verifier, reference="WAVE-654321", days=3, seed=7)
    assert payments.proof_seen_before(second) and payments.proof_seen_before(first)


def test_a_booking_that_moved_on_cannot_be_confirmed(paid, cashier):
    booking, payment = paid
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.CANCELLED)
    assert (
        code(
            lambda: payments.confirm_payment(
                payment, staff=cashier, amount_matches=True, reference_matches=True
            )
        )
        == "invalid_state"
    )
