from datetime import timedelta

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.bookings.models import Booking, Payout, Report
from tests.helpers import confirmed_booking
from tests.test_offers_api import bearer_for_user

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


def call(api_client, user, method, path, body=None):
    return getattr(api_client, method)(path, body, format="json", HTTP_AUTHORIZATION=bearer_for_user(user))


def mine(booking, tail=""):
    return f"/api/v1/my-bookings/{booking.pk}{tail}"


def offer(booking, tail=""):
    return f"/api/v1/my-offers/{booking.offer_id}/booking{tail}"


@pytest.fixture
def booking(verified_householder, jpeg, verifier):
    found = confirmed_booking(verified_householder, jpeg, verifier)
    Booking.objects.filter(pk=found.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    found.refresh_from_db()
    return found


def finish(api_client, booking):
    assert call(api_client, booking.jobber, "post", mine(booking, "/check-in"), {}).status_code == 200
    assert call(api_client, booking.jobber, "post", mine(booking, "/check-out")).status_code == 200
    return call(api_client, booking.householder, "post", offer(booking, "/confirm"))


def test_jobber_checks_in_and_out_through_the_api(api_client, booking):
    early = Booking.objects.filter(pk=booking.pk)
    early.update(starts_at=timezone.now() + timedelta(hours=5))
    response = call(api_client, booking.jobber, "post", mine(booking, "/check-in"), {"lat": 5.3, "lng": -4.0})
    assert response.status_code == 409 and response.json()["error"] == "checkin_too_early"
    early.update(starts_at=timezone.now() + timedelta(minutes=5))
    response = call(
        api_client,
        booking.jobber,
        "post",
        mine(booking, "/check-in"),
        {"lat": 5.3, "lng": -4.0, "accuracy_m": 12},
    )
    assert response.status_code == 200 and response.json() == {"id": str(booking.pk), "status": "checked_in"}
    response = call(api_client, booking.jobber, "post", mine(booking, "/check-out"))
    assert response.status_code == 200 and response.json()["status"] == "completion_pending"
    assert call(api_client, booking.jobber, "post", mine(booking, "/check-out")).status_code == 409


def test_householder_confirms_and_the_payout_exists(api_client, booking):
    response = finish(api_client, booking)
    assert response.status_code == 200 and response.json()["status"] == "completed"
    assert Payout.objects.get(booking=booking).amount_xof == booking.pay_xof
    assert call(api_client, booking.householder, "post", offer(booking, "/confirm")).status_code == 409


def test_report_and_dispute_through_the_api(api_client, booking):
    call(api_client, booking.jobber, "post", mine(booking, "/check-in"), {})
    concern = call(api_client, booking.jobber, "post", mine(booking, "/report"), {"text": "Le chien mord"})
    assert concern.status_code == 201 and concern.json()["kind"] == "concern"
    assert concern.json()["booking_status"] == "checked_in"
    bad = call(
        api_client, booking.householder, "post", offer(booking, "/report"), {"text": "a", "dispute": True}
    )
    assert bad.status_code == 400 and bad.json()["error"] == "report_invalid"
    dispute = call(
        api_client,
        booking.householder,
        "post",
        offer(booking, "/report"),
        {"text": "Rien de fait", "dispute": True},
    )
    assert dispute.status_code == 201 and dispute.json()["kind"] == "dispute"
    assert dispute.json()["booking_status"] == "disputed"
    assert Report.objects.filter(booking=booking).count() == 2
    detail = call(api_client, booking.householder, "get", offer(booking)).json()
    assert detail["status"] == "disputed" and "Le chien" not in str(detail)


def test_review_flow_through_the_api_hides_the_other_side_until_both_are_in(api_client, booking):
    finish(api_client, booking)
    assert call(api_client, booking.jobber, "get", mine(booking, "/review")).json() == {
        "mine": None,
        "theirs": None,
    }
    sent = call(
        api_client, booking.householder, "post", offer(booking, "/review"), {"stars": 4, "comment": "Sérieux"}
    )
    assert sent.status_code == 201 and sent.json() == {
        "mine": {"stars": 4, "comment": "Sérieux"},
        "theirs": None,
    }
    assert sent["Cache-Control"] == "no-store"
    assert call(api_client, booking.jobber, "get", mine(booking, "/review")).json()["theirs"] is None
    again = call(api_client, booking.householder, "post", offer(booking, "/review"), {"stars": 1})
    assert again.status_code == 409 and again.json()["error"] == "already_reviewed"
    leak = call(
        api_client,
        booking.jobber,
        "post",
        mine(booking, "/review"),
        {"stars": 5, "comment": "07 08 09 10 11"},
    )
    assert leak.status_code == 400 and leak.json()["error"] == "message_contact_details"
    assert call(api_client, booking.jobber, "post", mine(booking, "/review"), {"stars": 9}).status_code == 400
    both = call(api_client, booking.jobber, "post", mine(booking, "/review"), {"stars": 5})
    assert both.status_code == 201 and both.json()["theirs"] == {"stars": 4, "comment": "Sérieux"}
    seen = call(api_client, booking.householder, "get", offer(booking, "/review")).json()
    assert seen["theirs"] == {"stars": 5, "comment": ""}


def test_detail_and_rows_carry_the_new_fields(api_client, booking):
    row = call(api_client, booking.jobber, "get", "/api/v1/my-bookings").json()["results"][0]
    assert row["checked_in_at"] is None and row["payout"] == "none" and row["reviewable"] is False
    assert row["checkin_from"] and row["auto_confirm_at"] is None
    call(api_client, booking.jobber, "post", mine(booking, "/check-in"), {})
    call(api_client, booking.jobber, "post", mine(booking, "/check-out"))
    detail = call(api_client, booking.householder, "get", offer(booking)).json()
    assert detail["checked_in_at"] and detail["checked_out_at"] and detail["auto_confirm_at"]
    assert detail["reviewable"] is False and detail["jobber_rating"] is None
    call(api_client, booking.householder, "post", offer(booking, "/confirm"))
    # A completed booking is still shown to its householder.
    detail = call(api_client, booking.householder, "get", offer(booking))
    assert detail.status_code == 200
    assert detail.json()["status"] == "completed" and detail.json()["reviewable"] is True
    assert detail.json()["auto_confirm_at"] is None and detail.json()["cancellable"] is False
    row = call(api_client, booking.jobber, "get", "/api/v1/my-bookings").json()["results"][0]
    assert row["payout"] == "due" and row["reviewable"] is True and row["checked_out_at"]
    call(api_client, booking.jobber, "post", mine(booking, "/review"), {"stars": 5})
    row = call(api_client, booking.jobber, "get", "/api/v1/my-bookings").json()["results"][0]
    assert row["reviewable"] is False


def test_no_response_contains_the_other_sides_phone(api_client, booking):
    seen = []
    seen.append(call(api_client, booking.jobber, "post", mine(booking, "/check-in"), {}))
    seen.append(call(api_client, booking.jobber, "post", mine(booking, "/report"), {"text": "Une remarque"}))
    seen.append(
        call(api_client, booking.householder, "post", offer(booking, "/report"), {"text": "Une remarque"})
    )
    seen.append(call(api_client, booking.jobber, "post", mine(booking, "/check-out")))
    seen.append(call(api_client, booking.householder, "post", offer(booking, "/confirm")))
    seen.append(call(api_client, booking.householder, "get", offer(booking)))
    seen.append(call(api_client, booking.jobber, "get", "/api/v1/my-bookings"))
    seen.append(call(api_client, booking.householder, "post", offer(booking, "/review"), {"stars": 5}))
    seen.append(call(api_client, booking.jobber, "post", mine(booking, "/review"), {"stars": 5}))
    seen.append(call(api_client, booking.jobber, "get", mine(booking, "/review")))
    seen.append(call(api_client, booking.householder, "get", offer(booking, "/review")))
    for response in seen:
        assert response.status_code in (200, 201)
        text = response.content.decode()
        for phone in (booking.jobber.phone, booking.householder.phone):
            assert phone not in text and phone[-8:] not in text


def test_roles_and_foreign_ids(api_client, booking, verified_householder, jpeg, verifier):
    from tests.helpers import j1_jobber

    other = j1_jobber(jpeg, verifier)
    for tail in ("/check-in", "/check-out", "/report", "/review"):
        body = {"text": "Bonjour", "stars": 5}
        assert call(api_client, other, "post", mine(booking, tail), body).status_code == 404
        assert call(api_client, booking.householder, "post", mine(booking, tail), body).status_code == 403
    assert call(api_client, other, "get", mine(booking, "/review")).status_code == 404
    for tail in ("/confirm", "/report", "/review"):
        assert (
            call(api_client, booking.jobber, "post", offer(booking, tail), {"text": "x"}).status_code == 403
        )
    assert api_client.post(mine(booking, "/check-in"), {}, format="json").status_code in (401, 403)


def test_the_schema_validates():
    call_command("spectacular", "--validate", "--file", "/dev/null")
