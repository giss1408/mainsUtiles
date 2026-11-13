from datetime import timedelta

import pytest
from django.utils import timezone

from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment, PaymentMethod
from apps.bookings.services import payments
from apps.bookings.services.applications import BookingError
from apps.verification.services.encryption import decrypt_text
from tests.helpers import accepted_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def booking(verified_householder, jpeg, verifier):
    return accepted_booking(verified_householder, jpeg, verifier)


@pytest.fixture
def send(jpeg, payment_method):
    def _send(user, booking, **overrides):
        values = {
            "method_id": payment_method.pk,
            "reference": "WAVE-123456",
            "screenshot": jpeg(7),
            "captured_at": timezone.now(),
        }
        values.update(overrides)
        return payments.submit_proof(user, booking.pk, **values)

    return _send


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_proof_stores_an_encrypted_photo_and_moves_the_booking_to_review(booking, verified_householder, send):
    payment = send(verified_householder, booking)
    booking.refresh_from_db()
    assert booking.status == Booking.Status.PAYMENT_REVIEW
    assert payment.status == Payment.Status.SUBMITTED and payment.proof.kind == "payment_proof"
    assert payment.reference != "WAVE-123456" and decrypt_text(payment.reference) == "WAVE-123456"
    assert AdminAction.objects.filter(action="booking.payment.submit", actor=verified_householder).exists()


def test_amount_and_fee_follow_the_settings(booking, verified_householder, send, settings):
    settings.PLATFORM_FEE_PERCENT = 10
    payment = send(verified_householder, booking)
    assert (payment.fee_xof, payment.amount_xof) == (300, 3300)
    assert payments.payment_amount(booking) == (3300, 300)


def test_only_the_householder_of_an_accepted_booking_can_submit(
    booking, verified_householder, send, jpeg, verifier
):
    assert code(lambda: send(booking.jobber, booking)) == "forbidden"
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.CONFIRMED)
    assert code(lambda: send(verified_householder, booking)) == "invalid_state"
    assert (
        code(
            lambda: payments.submit_proof(
                verified_householder,
                "not-a-uuid",
                method_id=1,
                reference="ABCD1234",
                screenshot=b"",
                captured_at=timezone.now(),
            )
        )
        == "forbidden"
    )


def test_second_proof_while_one_is_under_review_is_invalid_state(booking, verified_householder, send):
    send(verified_householder, booking)
    assert code(lambda: send(verified_householder, booking, reference="WAVE-999999")) == "invalid_state"
    assert Payment.objects.count() == 1


def test_a_proof_after_the_window_or_the_release_time_is_refused(
    booking, verified_householder, send, settings
):
    Booking.objects.filter(pk=booking.pk).update(
        accepted_at=timezone.now() - timedelta(hours=settings.PAYMENT_WINDOW_HOURS, minutes=1)
    )
    assert code(lambda: send(verified_householder, booking)) == "payment_window_closed"
    fresh = Booking.objects.get(pk=booking.pk)
    Booking.objects.filter(pk=booking.pk).update(
        accepted_at=timezone.now(),
        starts_at=timezone.now() + timedelta(hours=settings.ADDRESS_RELEASE_HOURS - 1),
    )
    assert code(lambda: send(verified_householder, fresh)) == "payment_window_closed"


def test_reference_and_method_rules_each_have_their_code(booking, verified_householder, send, payment_method):
    for text in ("", "   ", "ab", "x" * 41, "REF<script>"):
        assert (
            code(lambda text=text: send(verified_householder, booking, reference=text)) == "reference_invalid"
        )
    assert code(lambda: send(verified_householder, booking, method_id=9999)) == "method_invalid"
    payment_method.active = False
    payment_method.save()
    assert code(lambda: send(verified_householder, booking)) == "payment_unavailable"
    other = PaymentMethod.objects.create(provider="mtn_momo", number="+2250505050505", active=False)
    payment_method.active = True
    payment_method.save()
    assert code(lambda: send(verified_householder, booking, method_id=other.pk)) == "method_invalid"
    assert not Payment.objects.exists()


def test_a_png_or_oversized_screenshot_is_refused_with_the_photo_codes(
    booking, verified_householder, send, settings
):
    assert code(lambda: send(verified_householder, booking, screenshot=b"\x89PNG....")) == "photo_invalid"
    settings.VERIFICATION_PHOTO_MAX_BYTES = 10
    assert code(lambda: send(verified_householder, booking)) == "photo_too_large"


def test_a_reference_is_trimmed_and_matched_without_case_or_spaces(booking, verified_householder, send):
    payment = send(verified_householder, booking, reference="  wave 123 456 ")
    assert payment.reference_hash == payments.reference_hash("WAVE-123456".replace("-", " "))


def test_after_a_refusal_a_new_proof_is_accepted(booking, verified_householder, send):
    first = send(verified_householder, booking)
    Payment.objects.filter(pk=first.pk).update(status=Payment.Status.REFUSED, reason="Montant faux")
    Booking.objects.filter(pk=booking.pk).update(status=Booking.Status.ACCEPTED)
    second = send(verified_householder, booking, reference="WAVE-777777")
    assert second.pk != first.pk and Payment.objects.filter(booking=booking).count() == 2
