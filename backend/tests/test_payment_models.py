import pytest
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction

from apps.bookings.models import Application, Booking, Payment, PaymentMethod
from apps.listings.models import Offer
from tests.helpers import j1_jobber, make_offer
from tests.test_booking_models import booking_for

pytestmark = pytest.mark.django_db


@pytest.fixture
def booking(verified_householder, jpeg, verifier):
    offer = make_offer(verified_householder)
    jobber = j1_jobber(jpeg, verifier)
    return booking_for(offer, Application.objects.create(offer=offer, jobber=jobber))


def make_payment(booking, jpeg, reference="TX-1001", status=Payment.Status.SUBMITTED, n=1):
    from django.utils import timezone

    from apps.verification.models import VerificationPhoto

    method = PaymentMethod.objects.get_or_create(
        provider="wave", defaults={"number": "+2250101010101", "active": True}
    )[0]
    proof = VerificationPhoto.objects.create(
        owner=booking.householder,
        kind="payment_proof",
        storage_name=f"proof-{booking.pk}-{n}.bin",
        sha256=f"{n:064d}",
        captured_at=timezone.now(),
    )
    return Payment.objects.create(
        booking=booking,
        method=method,
        amount_xof=booking.pay_xof,
        reference=reference,
        reference_hash=f"hash-{reference}",
        proof=proof,
        status=status,
    )


def test_available_methods_need_an_active_method_with_a_number():
    PaymentMethod.objects.create(provider="wave", number="", active=True)
    PaymentMethod.objects.create(provider="mtn_momo", number="+2250505050505", active=False)
    assert not PaymentMethod.objects.available().exists()
    PaymentMethod.objects.create(provider="orange_money", number="+2250707070707", active=True)
    assert [m.provider for m in PaymentMethod.objects.available()] == ["orange_money"]


def test_one_open_payment_per_booking(booking, jpeg):
    make_payment(booking, jpeg, "TX-1")
    with pytest.raises(IntegrityError), transaction.atomic():
        make_payment(booking, jpeg, "TX-2", n=2)
    refused = Payment.objects.get()
    refused.status = Payment.Status.REFUSED
    refused.save()
    make_payment(booking, jpeg, "TX-2", n=2)


def test_a_reference_confirms_only_one_booking(booking, verified_householder, jpeg, verifier):
    make_payment(booking, jpeg, "TX-SAME", Payment.Status.CONFIRMED)
    other_offer = make_offer(verified_householder, days=3)
    other = booking_for(
        other_offer, Application.objects.create(offer=other_offer, jobber=j1_jobber(jpeg, verifier))
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        make_payment(other, jpeg, "TX-SAME", Payment.Status.CONFIRMED, n=2)
    make_payment(other, jpeg, "TX-SAME", Payment.Status.SUBMITTED, n=3)  # a proof still waiting is fine


def test_payment_review_is_a_live_status_and_blocks_a_second_booking(booking, jpeg, verifier):
    booking.status = Booking.Status.PAYMENT_REVIEW
    booking.save()
    assert Booking.Status.PAYMENT_REVIEW in Booking.LIVE
    again = Application.objects.create(offer=booking.offer, jobber=j1_jobber(jpeg, verifier))
    with pytest.raises(IntegrityError), transaction.atomic():
        booking_for(booking.offer, again)
    assert Offer.objects.filter(pk=booking.offer_id).exists()


def test_group_payment_agent_has_its_permissions():
    group = Group.objects.get(name="payment_agent")
    codenames = set(group.permissions.values_list("codename", flat=True))
    assert {
        "verify_payment",
        "make_refund",
        "view_payment",
        "add_paymentmethod",
        "change_paymentmethod",
    } <= codenames
    assert "delete_paymentmethod" not in codenames
