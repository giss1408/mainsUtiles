from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.accounts.models import User
from apps.bookings.models import Booking
from apps.bookings.services import payments
from tests.helpers import accepted_booking, paid_booking
from tests.test_offers_api import bearer_for_user

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


def call(api_client, user, method, path, body=None, fmt="json"):
    return getattr(api_client, method)(path, body, format=fmt, HTTP_AUTHORIZATION=bearer_for_user(user))


def offer_path(booking, tail=""):
    return f"/api/v1/my-offers/{booking.offer_id}/booking{tail}"


def test_booking_detail_shows_methods_amount_and_the_first_name_only_until_confirmed(
    api_client, verified_householder, jpeg, verifier, payment_method
):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    body = call(api_client, verified_householder, "get", offer_path(booking)).json()
    assert body["status"] == "accepted" and body["amount_xof"] == 3000 and body["fee_xof"] == 0
    assert body["methods"][0]["number"] == "+2250101010101" and body["methods"][0]["provider"] == "wave"
    assert body["jobber"] == {"first_name": "Jeune"} and body["payment"] is None
    assert body["cancellable"] is True and body["pay_deadline"]
    assert "Jobber" not in str(body)


def test_detail_shows_the_full_name_after_confirmation(
    api_client, verified_householder, jpeg, verifier, cashier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    review = call(api_client, verified_householder, "get", offer_path(booking)).json()
    assert review["status"] == "payment_review" and review["payment"]["status"] == "submitted"
    assert review["jobber"] == {"first_name": "Jeune"}
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    done = call(api_client, verified_householder, "get", offer_path(booking)).json()
    assert done["status"] == "confirmed" and done["jobber"] == {
        "full_name": "Jeune Jobber",
        "has_photo": True,
    }


def test_a_refused_payment_shows_its_reason(api_client, verified_householder, jpeg, verifier, cashier):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    payments.refuse_payment(payment, staff=cashier, reason="Montant reçu : 2 000 FCFA")
    body = call(api_client, verified_householder, "get", offer_path(booking)).json()
    assert body["status"] == "accepted"
    assert body["payment"] == {"status": "refused", "reason": "Montant reçu : 2 000 FCFA"}


def test_payment_upload_creates_a_submitted_payment_and_validates_the_fields(
    api_client, verified_householder, jpeg, verifier, payment_method
):
    booking = accepted_booking(verified_householder, jpeg, verifier)

    def upload(**overrides):
        data = {
            "method_id": payment_method.pk,
            "reference": "WAVE-123456",
            "screenshot": SimpleUploadedFile("proof.jpg", jpeg(7), "image/jpeg"),
            "captured_at": timezone.now().isoformat(),
        }
        data.update(overrides)
        return call(
            api_client, verified_householder, "post", offer_path(booking, "/payment"), data, "multipart"
        )

    bad = upload(reference="ab")
    assert bad.status_code == 400 and bad.json()["error"] == "reference_invalid"
    png = upload(screenshot=SimpleUploadedFile("p.png", b"\x89PNG....", "image/png"))
    assert png.status_code == 400 and png.json()["error"] == "photo_invalid"
    good = upload()
    assert good.status_code == 201 and good.json()["status"] == "submitted"
    again = upload(reference="WAVE-999999")
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"
    assert Booking.objects.get(pk=booking.pk).status == "payment_review"


def test_photo_endpoint_is_no_store_and_householder_only(
    api_client, verified_householder, jpeg, verifier, cashier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    assert call(api_client, verified_householder, "get", offer_path(booking, "/photo")).status_code == 409
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    response = call(api_client, verified_householder, "get", offer_path(booking, "/photo"))
    assert response.status_code == 200 and response["Content-Type"] == "image/jpeg"
    assert "no-store" in response["Cache-Control"]
    assert call(api_client, booking.jobber, "get", offer_path(booking, "/photo")).status_code == 403


def test_address_endpoint_obeys_the_window(
    api_client, verified_householder, jpeg, verifier, cashier, settings
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    path = f"/api/v1/my-bookings/{booking.pk}/address"
    early = call(api_client, booking.jobber, "get", path)
    assert early.status_code == 409 and early.json()["error"] == "address_not_yet"
    Booking.objects.filter(pk=booking.pk).update(
        starts_at=timezone.now() + timedelta(hours=settings.ADDRESS_RELEASE_HOURS - 1)
    )
    ok = call(api_client, booking.jobber, "get", path)
    assert ok.status_code == 200 and set(ok.json()) == {"latitude", "longitude", "commune", "quartier"}
    assert "no-store" in ok["Cache-Control"]
    rows = call(api_client, booking.jobber, "get", "/api/v1/my-bookings").json()["results"]
    assert rows[0]["status"] == "address_released" and rows[0]["payment"] == "confirmed"
    assert call(api_client, verified_householder, "get", path).status_code == 403


def test_my_bookings_tells_the_jobber_when_the_address_comes(
    api_client, verified_householder, jpeg, verifier
):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    row = call(api_client, booking.jobber, "get", "/api/v1/my-bookings").json()["results"][0]
    assert row["payment"] == "pending" and row["address_available_from"]
    assert "latitude" not in str(row)


def test_cancel_from_both_sides(api_client, verified_householder, jpeg, verifier):
    one = accepted_booking(verified_householder, jpeg, verifier)
    two = accepted_booking(verified_householder, jpeg, verifier, days=3)
    mine = call(
        api_client, verified_householder, "post", offer_path(one, "/cancel"), {"reason": "Changement"}
    )
    assert mine.status_code == 200 and mine.json()["status"] == "cancelled"
    theirs = call(
        api_client, two.jobber, "post", f"/api/v1/my-bookings/{two.pk}/cancel", {"reason": "Malade"}
    )
    assert theirs.status_code == 200 and theirs.json()["status"] == "cancelled"
    again = call(api_client, two.jobber, "post", f"/api/v1/my-bookings/{two.pk}/cancel", {})
    assert again.status_code == 409


def test_no_response_contains_the_other_sides_phone(
    api_client, verified_householder, jpeg, verifier, cashier
):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    householder_side = call(api_client, verified_householder, "get", offer_path(booking)).content.decode()
    assert booking.jobber.phone not in householder_side
    jobber_side = " ".join(
        call(api_client, booking.jobber, "get", path).content.decode()
        for path in ("/api/v1/my-bookings", f"/api/v1/my-bookings/{booking.pk}/address")
    )
    assert verified_householder.phone not in jobber_side and str(verified_householder.pk) not in jobber_side


def test_foreign_ids_are_404(api_client, verified_householder, jpeg, verifier):
    booking = accepted_booking(verified_householder, jpeg, verifier)
    stranger = User.objects.create_user(phone="+2250606060606", role="householder")
    assert call(api_client, stranger, "get", offer_path(booking)).status_code == 404
    other_jobber = accepted_booking(verified_householder, jpeg, verifier, days=3).jobber
    assert (
        call(api_client, other_jobber, "get", f"/api/v1/my-bookings/{booking.pk}/address").status_code == 404
    )
    assert (
        call(api_client, other_jobber, "post", f"/api/v1/my-bookings/{booking.pk}/cancel").status_code == 404
    )
