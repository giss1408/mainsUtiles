from contextlib import nullcontext
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from apps.accounts.models import Device, User
from apps.accounts.services.device_auth import issue_tokens
from apps.listings.models import Offer, OfferCategory

pytestmark = pytest.mark.django_db

# These tests run on the real clock, so that access tokens stay valid. Dates are relative to today.
freeze_time = lambda _: nullcontext()  # noqa: E731
BASE = "/api/v1"
ABIDJAN = ZoneInfo("Africa/Abidjan")


def bearer_for_user(api_client, user):
    """A bearer token for the user's active device; the device is created once."""
    import uuid

    device = Device.objects.filter(user=user, status=Device.Status.ACTIVE).first()
    if device is None:
        device = Device.objects.create(
            id=uuid.uuid4(),
            user=user,
            public_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            model="Test",
            platform="android",
        )
    return f"Bearer {issue_tokens(device).access}"


def iso(day, hour, minute=0):
    today = datetime.now(ABIDJAN).date()
    local = datetime(today.year, today.month, today.day, tzinfo=ABIDJAN) + timedelta(days=day)
    return local.replace(hour=hour, minute=minute).astimezone(UTC).isoformat()


@pytest.fixture
def menage():
    return OfferCategory.objects.get(name="Ménage")


@pytest.fixture
def body(menage):
    return {
        "category_id": menage.pk,
        "duties": ["Dépoussiérer"],
        "starts_at": iso(1, 9),
        "duration_minutes": 180,
        "pay_xof": 3000,
        "note": "",
    }


def test_every_route_needs_a_token(api_client, body):
    with freeze_time(None):
        routes = [
            ("get", f"{BASE}/offer-categories"),
            ("get", f"{BASE}/my-offers"),
            ("post", f"{BASE}/my-offers"),
            ("patch", f"{BASE}/my-offers/00000000-0000-4000-8000-000000000000"),
            ("delete", f"{BASE}/my-offers/00000000-0000-4000-8000-000000000000"),
            ("post", f"{BASE}/my-offers/00000000-0000-4000-8000-000000000000/send"),
        ]
        for method, path in routes:
            response = getattr(api_client, method)(path, body, format="json")
            assert response.status_code == 401, path


def test_jobber_and_staff_are_refused_on_every_route(api_client, body, enrolled, staff_user, make_device):
    jobber = bearer_for_user(api_client, enrolled.device.user)
    staff = bearer_for_user(api_client, make_device(staff_user).user)
    with freeze_time(None):
        for bearer in (jobber, staff):
            assert api_client.get(f"{BASE}/offer-categories", HTTP_AUTHORIZATION=bearer).status_code == 403
            assert api_client.get(f"{BASE}/my-offers", HTTP_AUTHORIZATION=bearer).status_code == 403
            assert (
                api_client.post(
                    f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=bearer
                ).status_code
                == 403
            )


def test_categories_and_limits(api_client, verified_householder):
    with freeze_time(None):
        response = api_client.get(
            f"{BASE}/offer-categories", HTTP_AUTHORIZATION=bearer_for_user(api_client, verified_householder)
        )
    assert response.status_code == 200
    data = response.json()
    assert [c["name"] for c in data["categories"]] == [
        "Ménage",
        "Cuisine",
        "Accompagnement d'une personne âgée",
    ]
    menage = data["categories"][0]
    assert menage["durations_minutes"] == [120, 180, 240]
    assert (menage["suggested_pay_min"], menage["suggested_pay_max"]) == (2000, 5000)
    assert data["limits"] == {
        "earliest_start": "06:00",
        "latest_end": "19:00",
        "min_pay": 1000,
        "max_pay": 100000,
        "max_days_ahead": 30,
        "note_max_length": 300,
    }


def test_create_edit_send_withdraw_copy_round_trip(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        created = api_client.post(f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=bearer)
        assert created.status_code == 201
        offer = created.json()
        assert offer["status"] == "draft" and offer["commune"] == "" and offer["category_name"] == ""

        edited = api_client.patch(
            f"{BASE}/my-offers/{offer['id']}", {"pay_xof": 4000}, format="json", HTTP_AUTHORIZATION=bearer
        )
        assert edited.status_code == 200 and edited.json()["pay_xof"] == 4000

        sent = api_client.post(f"{BASE}/my-offers/{offer['id']}/send", HTTP_AUTHORIZATION=bearer)
        assert sent.status_code == 200
        sent_body = sent.json()
        assert sent_body["status"] == "in_review"
        assert (sent_body["commune"], sent_body["quartier"], sent_body["category_name"]) == (
            "Cocody",
            "Angré",
            "Ménage",
        )

        withdrawn = api_client.post(f"{BASE}/my-offers/{offer['id']}/withdraw", HTTP_AUTHORIZATION=bearer)
        assert withdrawn.json()["status"] == "withdrawn"

        copied = api_client.post(f"{BASE}/my-offers/{offer['id']}/copy", HTTP_AUTHORIZATION=bearer)
        assert copied.status_code == 201 and copied.json()["status"] == "draft"


def test_h0_householder_gets_verification_required_and_cannot_publish(api_client, householder, body):
    with freeze_time(None):
        bearer = bearer_for_user(api_client, householder)
        listing = api_client.get(f"{BASE}/my-offers", HTTP_AUTHORIZATION=bearer)
        assert listing.status_code == 200 and listing.json()["can_publish"] is False
        response = api_client.post(f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=bearer)
        assert response.status_code == 403
        assert response.json() == {
            "error": "verification_required",
            "message": "Faites vérifier votre compte pour publier une offre.",
        }


@pytest.mark.parametrize(
    ("field", "value", "code"),
    [
        ("duties", [], "duties_invalid"),
        ("duration_minutes", 90, "duration_invalid"),
        ("pay_xof", 999, "pay_invalid"),
        ("pay_xof", 100001, "pay_invalid"),
        ("note", "x" * 301, "note_too_long"),
        ("category_id", 999999, "category_invalid"),
        ("starts_at", "__past__", "time_invalid"),
    ],
)
def test_invalid_fields_give_400_with_the_french_message(
    api_client, verified_householder, body, field, value, code
):
    bearer = bearer_for_user(api_client, verified_householder)
    if value == "__past__":
        value = iso(-1, 9)
    with freeze_time(None):
        response = api_client.post(
            f"{BASE}/my-offers", body | {field: value}, format="json", HTTP_AUTHORIZATION=bearer
        )
    assert response.status_code == 400 and response.json()["error"] == code
    assert response.json()["message"]


def test_too_many_open_offers_is_409(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        for day in (1, 2, 3):
            created = api_client.post(
                f"{BASE}/my-offers",
                body | {"starts_at": iso(day, 9)},
                format="json",
                HTTP_AUTHORIZATION=bearer,
            )
            api_client.post(f"{BASE}/my-offers/{created.json()['id']}/send", HTTP_AUTHORIZATION=bearer)
        fourth = api_client.post(
            f"{BASE}/my-offers", body | {"starts_at": iso(4, 9)}, format="json", HTTP_AUTHORIZATION=bearer
        )
        response = api_client.post(f"{BASE}/my-offers/{fourth.json()['id']}/send", HTTP_AUTHORIZATION=bearer)
    assert response.status_code == 409 and response.json()["error"] == "too_many_offers"


def test_send_twice_is_409(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        offer = api_client.post(f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=bearer).json()
        api_client.post(f"{BASE}/my-offers/{offer['id']}/send", HTTP_AUTHORIZATION=bearer)
        again = api_client.post(f"{BASE}/my-offers/{offer['id']}/send", HTTP_AUTHORIZATION=bearer)
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"


def test_delete_only_drafts(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        offer = api_client.post(f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=bearer).json()
        assert (
            api_client.delete(f"{BASE}/my-offers/{offer['id']}", HTTP_AUTHORIZATION=bearer).status_code == 204
        )
        sent = api_client.post(
            f"{BASE}/my-offers", body | {"starts_at": iso(2, 9)}, format="json", HTTP_AUTHORIZATION=bearer
        ).json()
        api_client.post(f"{BASE}/my-offers/{sent['id']}/send", HTTP_AUTHORIZATION=bearer)
        response = api_client.delete(f"{BASE}/my-offers/{sent['id']}", HTTP_AUTHORIZATION=bearer)
    assert response.status_code == 409 and response.json()["error"] == "invalid_state"


def test_other_householders_offer_is_404_on_every_route(api_client, verified_householder, body, enrol_device):
    owner = bearer_for_user(api_client, verified_householder)
    intruder = User.objects.create_user(phone="+2250707070707", role="householder")
    other = bearer_for_user(api_client, intruder)
    with freeze_time(None):
        offer = api_client.post(f"{BASE}/my-offers", body, format="json", HTTP_AUTHORIZATION=owner).json()
        oid = offer["id"]
        assert (
            api_client.patch(
                f"{BASE}/my-offers/{oid}", {"pay_xof": 4000}, format="json", HTTP_AUTHORIZATION=other
            ).status_code
            == 404
        )
        assert api_client.delete(f"{BASE}/my-offers/{oid}", HTTP_AUTHORIZATION=other).status_code == 404
        for action in ("send", "withdraw", "copy"):
            assert (
                api_client.post(f"{BASE}/my-offers/{oid}/{action}", HTTP_AUTHORIZATION=other).status_code
                == 404
            )
    assert Offer.objects.get(pk=oid).pay_xof == 3000


def test_response_never_contains_flags_or_the_refusal_reason(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        offer = api_client.post(
            f"{BASE}/my-offers", body | {"note": "Voyage prévu"}, format="json", HTTP_AUTHORIZATION=bearer
        ).json()
        sent = api_client.post(f"{BASE}/my-offers/{offer['id']}/send", HTTP_AUTHORIZATION=bearer)
        listing = api_client.get(f"{BASE}/my-offers", HTTP_AUTHORIZATION=bearer)
    assert sent.json()["status"] == "in_review"
    assert "flags" not in sent.json() and "travel" not in sent.content.decode()  # the flag name
    assert "flags" not in listing.content.decode()
    assert set(sent.json()) == {
        "id",
        "category_id",
        "category_name",
        "duties",
        "starts_at",
        "duration_minutes",
        "pay_xof",
        "note",
        "commune",
        "quartier",
        "status",
        "reason",
        "created_at",
        "applicants_count",
        "booking",
    }


def test_my_offers_lists_newest_first_with_review_hours(api_client, verified_householder, body):
    bearer = bearer_for_user(api_client, verified_householder)
    with freeze_time(None):
        api_client.post(
            f"{BASE}/my-offers", body | {"starts_at": iso(1, 9)}, format="json", HTTP_AUTHORIZATION=bearer
        )
        api_client.post(
            f"{BASE}/my-offers", body | {"starts_at": iso(2, 9)}, format="json", HTTP_AUTHORIZATION=bearer
        )
        data = api_client.get(f"{BASE}/my-offers", HTTP_AUTHORIZATION=bearer).json()
    assert data["can_publish"] is True and data["review_hours"] == 24
    days = [o["starts_at"][:10] for o in data["offers"]]
    assert days == sorted(days, reverse=True) and len(days) == 2
