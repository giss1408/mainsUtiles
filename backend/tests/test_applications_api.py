import pytest

from apps.bookings.models import Application
from apps.bookings.services import applications
from tests.helpers import j1_jobber, make_offer
from tests.test_offers_api import bearer_for_user

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


@pytest.fixture
def offer(verified_householder):
    return make_offer(verified_householder)


def call(api_client, user, method, path, body=None):
    return getattr(api_client, method)(path, body, format="json", HTTP_AUTHORIZATION=bearer_for_user(user))


def test_apply_returns_201_and_the_list_shows_it(api_client, jobber, offer):
    response = call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {"message": "Bonjour"})
    assert response.status_code == 201
    body = response.json()
    assert set(body) == {"id", "offer_id", "status", "created_at"} and body["status"] == "pending"
    rows = call(api_client, jobber, "get", "/api/v1/my-applications").json()["results"]
    assert [r["id"] for r in rows] == [body["id"]]
    assert rows[0]["offer"]["category_name"] == "Ménage" and rows[0]["booking"] is None
    assert rows[0]["message"] == "Bonjour"


@pytest.mark.parametrize(
    ("message", "status", "error"),
    [
        ("07 08 09 10 11", 400, "message_contact_details"),
        ("a" * 201, 400, "message_too_long"),
    ],
)
def test_message_errors_have_their_status_and_a_french_message(
    api_client, jobber, offer, message, status, error
):
    response = call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {"message": message})
    assert response.status_code == status and response.json()["error"] == error
    assert response.json()["message"]


def test_unverified_jobber_and_double_application_and_unknown_offer(api_client, jobber, offer, enrolled):
    partial = enrolled.device.user  # enrolled, nothing verified
    response = call(api_client, partial, "post", f"/api/v1/offers/{offer.pk}/apply", {})
    assert (response.status_code, response.json()["error"]) == (403, "jobber_verification_required")
    call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {})
    again = call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {})
    assert (again.status_code, again.json()["error"]) == (409, "already_applied")
    missing = call(
        api_client, jobber, "post", "/api/v1/offers/00000000-0000-0000-0000-000000000000/apply", {}
    )
    assert (missing.status_code, missing.json()["error"]) == (409, "offer_unavailable")


def test_offer_detail_carries_the_trust_line_and_my_application(api_client, jobber, offer):
    before = call(api_client, jobber, "get", f"/api/v1/offers/{offer.pk}").json()
    assert before["householder"] == {"tier": "H1", "jobs_done": 0, "rating": None}
    assert before["my_application"] is None
    applied = call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {}).json()
    after = call(api_client, jobber, "get", f"/api/v1/offers/{offer.pk}").json()
    assert after["my_application"] == {"id": applied["id"], "status": "pending"}


def test_no_jobber_response_contains_the_householder_name_phone_or_id(
    api_client, jobber, offer, verified_householder
):
    call(api_client, jobber, "post", f"/api/v1/offers/{offer.pk}/apply", {"message": "ok"})
    paths = [f"/api/v1/offers/{offer.pk}", "/api/v1/my-applications", "/api/v1/my-bookings"]
    raw = " ".join(call(api_client, jobber, "get", path).content.decode() for path in paths)
    assert verified_householder.phone not in raw
    assert str(verified_householder.pk) not in raw
    assert "author" not in raw and "householder_id" not in raw


def test_my_bookings_shows_the_accepted_booking_without_address(
    api_client, jobber, offer, verified_householder
):
    application = applications.apply(jobber, offer.pk, "")
    applications.accept(verified_householder, application.pk)
    rows = call(api_client, jobber, "get", "/api/v1/my-bookings").json()["results"]
    assert len(rows) == 1 and rows[0]["status"] == "accepted"
    assert set(rows[0]) == {
        "id",
        "status",
        "category_name",
        "starts_at",
        "duration_minutes",
        "pay_xof",
        "commune",
        "quartier",
        "address_available_from",
        "payment",
    }
    listed = call(api_client, jobber, "get", "/api/v1/my-applications").json()["results"][0]
    assert listed["booking"]["status"] == "accepted" and listed["status"] == "accepted"


def test_withdraw_works_and_someone_elses_application_is_404(api_client, jobber, offer, jpeg, verifier):
    application = applications.apply(jobber, offer.pk, "")
    other = j1_jobber(jpeg, verifier)
    stranger = call(api_client, other, "post", f"/api/v1/my-applications/{application.pk}/withdraw")
    assert stranger.status_code == 404
    mine = call(api_client, jobber, "post", f"/api/v1/my-applications/{application.pk}/withdraw")
    assert mine.status_code == 200 and mine.json()["status"] == "withdrawn"
    again = call(api_client, jobber, "post", f"/api/v1/my-applications/{application.pk}/withdraw")
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"
    assert Application.objects.get(pk=application.pk).status == "withdrawn"


def test_householder_gets_403_on_jobber_routes(api_client, verified_householder, offer):
    for method, path in [
        ("post", f"/api/v1/offers/{offer.pk}/apply"),
        ("get", "/api/v1/my-applications"),
        ("get", "/api/v1/my-bookings"),
    ]:
        assert call(api_client, verified_householder, method, path).status_code == 403
