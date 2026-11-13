from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment
from apps.bookings.services import bookings, payments
from apps.bookings.services.errors import BookingError
from apps.listings.models import Offer
from apps.listings.services import offers as offer_service
from apps.verification.services.encryption import decrypt_text
from tests.helpers import accepted_booking, paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def confirm(payment, cashier):
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)


def test_householder_and_jobber_can_cancel_before_check_in_others_cannot(
    verified_householder, jpeg, verifier
):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    stranger = accepted_booking(verified_householder, jpeg, verifier, days=3).jobber
    assert code(lambda: bookings.cancel(stranger, booking.pk)) == "forbidden"
    assert code(lambda: bookings.cancel(verified_householder, "not-a-uuid")) == "forbidden"
    cancelled = bookings.cancel(booking.jobber, booking.pk, reason="Imprévu")
    assert cancelled.status == Booking.Status.CANCELLED and cancelled.cancelled_by == booking.jobber
    assert cancelled.cancelled_at and cancelled.cancel_reason == "Imprévu"
    assert AdminAction.objects.filter(action="booking.cancel", actor=booking.jobber).exists()
    assert code(lambda: bookings.cancel(verified_householder, booking.pk)) == "invalid_state"
    for status in ("checked_in", "completion_pending", "completed", "disputed"):
        other = accepted_booking(verified_householder, jpeg, verifier, days=4)
        Booking.objects.filter(pk=other.pk).update(status=status)
        assert code(lambda o=other: bookings.cancel(verified_householder, o.pk)) == "invalid_state"


def test_cancel_of_a_paid_booking_makes_the_payment_refund_due_once(
    verified_householder, jpeg, verifier, cashier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    confirm(payment, cashier)
    bookings.cancel(verified_householder, booking.pk)
    payment.refresh_from_db()
    assert payment.status == Payment.Status.REFUND_DUE
    assert code(lambda: bookings.cancel(verified_householder, booking.pk)) == "invalid_state"
    assert Payment.objects.filter(status=Payment.Status.REFUND_DUE).count() == 1


def test_cancelling_while_the_proof_is_under_review_also_asks_for_a_refund(
    verified_householder, jpeg, verifier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    bookings.cancel(verified_householder, booking.pk)
    payment.refresh_from_db()
    assert payment.status == Payment.Status.REFUND_DUE


def test_an_unpaid_booking_cancels_without_a_refund(verified_householder, jpeg, verifier):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    bookings.cancel(verified_householder, booking.pk)
    assert not Payment.objects.exists()


def test_cancel_reopens_the_offer_only_if_it_has_not_started(verified_householder, jpeg, verifier):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    bookings.cancel(verified_householder, booking.pk)
    booking.offer.refresh_from_db()
    assert booking.offer.status == Offer.Status.PUBLISHED
    started = accepted_booking(verified_householder, jpeg, verifier, days=3)
    Offer.objects.filter(pk=started.offer_id).update(starts_at=timezone.now() - timedelta(minutes=5))
    Booking.objects.filter(pk=started.pk).update(starts_at=timezone.now() - timedelta(minutes=5))
    bookings.cancel(verified_householder, started.pk)
    started.offer.refresh_from_db()
    assert started.offer.status == Offer.Status.CLOSED


def test_expire_unpaid_expires_only_bookings_without_a_proof(verified_householder, jpeg, verifier, settings):
    late = accepted_booking(verified_householder, jpeg, verifier, days=3)
    fresh = accepted_booking(verified_householder, jpeg, verifier, days=4)
    soon = accepted_booking(verified_householder, jpeg, verifier, days=5)
    Booking.objects.filter(pk=late.pk).update(
        accepted_at=timezone.now() - timedelta(hours=settings.PAYMENT_WINDOW_HOURS, minutes=1)
    )
    Booking.objects.filter(pk=soon.pk).update(
        starts_at=timezone.now() + timedelta(hours=settings.ADDRESS_RELEASE_HOURS - 1)
    )
    assert bookings.expire_unpaid() == 2
    for row, status in ((late, "expired"), (soon, "expired"), (fresh, "accepted")):
        row.refresh_from_db()
        assert row.status == status
    late.offer.refresh_from_db()
    assert late.offer.status == Offer.Status.PUBLISHED


def test_a_booking_under_review_never_expires(verified_householder, jpeg, verifier, settings):
    booking, _ = paid_booking(verified_householder, jpeg, verifier)
    Booking.objects.filter(pk=booking.pk).update(
        accepted_at=timezone.now() - timedelta(hours=settings.PAYMENT_WINDOW_HOURS * 3)
    )
    assert bookings.expire_unpaid() == 0
    booking.refresh_from_db()
    assert booking.status == Booking.Status.PAYMENT_REVIEW


def test_record_refund_needs_the_permission_a_reference_and_happens_once(
    verified_householder, jpeg, verifier, cashier, staff_user
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    confirm(payment, cashier)
    bookings.cancel(verified_householder, booking.pk)
    assert code(lambda: payments.record_refund(payment, staff=staff_user, reference="RB-1")) == "forbidden"
    assert code(lambda: payments.record_refund(payment, staff=cashier, reference="  ")) == "reference_invalid"
    payments.record_refund(payment, staff=cashier, reference="RB-2001")
    payment.refresh_from_db()
    assert payment.status == Payment.Status.REFUNDED and decrypt_text(payment.refund_reference) == "RB-2001"
    assert payment.refunded_by == cashier and payment.refunded_at
    assert AdminAction.objects.filter(action="booking.payment.refund", actor=cashier).exists()
    assert (
        code(lambda: payments.record_refund(payment, staff=cashier, reference="RB-2002")) == "invalid_state"
    )


def test_withdrawing_a_booked_offer_goes_through_cancel(verified_householder, jpeg, verifier):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    offer_service.withdraw(booking.offer, user=verified_householder)
    booking.refresh_from_db()
    payment.refresh_from_db()
    booking.offer.refresh_from_db()
    assert booking.status == Booking.Status.CANCELLED and payment.status == Payment.Status.REFUND_DUE
    assert booking.offer.status == Offer.Status.WITHDRAWN


def test_a_confirmed_booking_can_no_longer_be_withdrawn_silently(
    verified_householder, jpeg, verifier, cashier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    confirm(payment, cashier)
    # Withdrawing the offer of a paid booking is a cancellation: the householder cancels the booking.
    with pytest.raises(offer_service.OfferError) as caught:
        offer_service.withdraw(booking.offer, user=verified_householder)
    assert caught.value.code == "invalid_state"


def test_the_sweep_task_runs(verified_householder):
    from apps.bookings.tasks import expire_unpaid_bookings

    assert expire_unpaid_bookings() == 0
