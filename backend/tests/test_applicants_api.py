import pytest

from apps.bookings.services import applications
from tests.helpers import j1_jobber, make_offer
from tests.test_offers_api import bearer_for_user

pytestmark = pytest.mark.django_db


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


@pytest.fixture
def offer(verified_householder):
    return make_offer(verified_householder)


def call(api_client, user, method, path, body=None):
    return getattr(api_client, method)(path, body, format="json", HTTP_AUTHORIZATION=bearer_for_user(user))


def test_applicants_endpoint_lists_only_pending_with_no_phone_or_last_name(
    api_client, verified_householder, offer, jobber, jpeg, verifier
):
    other = j1_jobber(jpeg, verifier)
    applications.apply(jobber, offer.pk, "Bonjour")
    gone = applications.apply(other, offer.pk, "")
    applications.withdraw(other, gone.pk)
    response = call(api_client, verified_householder, "get", f"/api/v1/my-offers/{offer.pk}/applicants")
    rows = response.json()["results"]
    assert len(rows) == 1 and rows[0]["first_name"] == "Jeune" and rows[0]["message"] == "Bonjour"
    raw = response.content.decode()
    assert jobber.phone not in raw and "Jobber" not in raw and str(jobber.pk) not in raw


def test_accept_returns_the_booking_and_the_offer_shows_booked(
    api_client, verified_householder, offer, jobber
):
    application = applications.apply(jobber, offer.pk, "")
    response = call(
        api_client,
        verified_householder,
        "post",
        f"/api/v1/my-offers/{offer.pk}/applicants/{application.pk}/accept",
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "accepted" and body["jobber_first_name"] == "Jeune" and body["pay_xof"] == 3000
    assert jobber.phone not in response.content.decode()
    detail = call(api_client, verified_householder, "get", "/api/v1/my-offers").json()["offers"][0]
    assert detail["status"] == "booked" and detail["applicants_count"] == 0
    assert detail["booking"] == {"id": body["id"], "status": "accepted", "jobber_first_name": "Jeune"}


def test_accept_twice_is_409(api_client, verified_householder, offer, jobber):
    application = applications.apply(jobber, offer.pk, "")
    path = f"/api/v1/my-offers/{offer.pk}/applicants/{application.pk}/accept"
    call(api_client, verified_householder, "post", path)
    again = call(api_client, verified_householder, "post", path)
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"


def test_other_householders_offer_is_404(api_client, verified_householder, offer, jobber, db):
    from apps.accounts.models import User

    stranger = User.objects.create_user(phone="+2250606060606", role="householder")
    application = applications.apply(jobber, offer.pk, "")
    assert call(api_client, stranger, "get", f"/api/v1/my-offers/{offer.pk}/applicants").status_code == 404
    path = f"/api/v1/my-offers/{offer.pk}/applicants/{application.pk}/accept"
    assert call(api_client, stranger, "post", path).status_code == 404
    other_offer = make_offer(verified_householder, days=3)
    wrong = f"/api/v1/my-offers/{other_offer.pk}/applicants/{application.pk}/accept"
    assert call(api_client, verified_householder, "post", wrong).status_code == 404


def test_jobber_gets_403_on_householder_routes(api_client, offer, jobber):
    assert call(api_client, jobber, "get", f"/api/v1/my-offers/{offer.pk}/applicants").status_code == 403


def test_my_offers_carry_applicants_count_and_booking(api_client, verified_householder, offer, jobber):
    applications.apply(jobber, offer.pk, "")
    row = call(api_client, verified_householder, "get", "/api/v1/my-offers").json()["offers"][0]
    assert row["applicants_count"] == 1 and row["booking"] is None
