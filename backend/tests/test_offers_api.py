from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from django.utils import timezone

from apps.accounts.models import Device
from apps.accounts.services.device_auth import issue_tokens
from apps.listings.models import Offer, OfferCategory

pytestmark = pytest.mark.django_db

BASE = "/api/v1/offers"
ABIDJAN = ZoneInfo("Africa/Abidjan")
PUBLIC_KEYS = {
    "id",
    "category_name",
    "duties",
    "starts_at",
    "duration_minutes",
    "pay_xof",
    "note",
    "commune",
    "quartier",
}


def bearer_for_user(user):
    import uuid

    device = Device.objects.filter(user=user, status=Device.Status.ACTIVE).first()
    if device is None:
        device = Device.objects.create(
            id=uuid.uuid4(),
            user=user,
            public_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            model="T",
            platform="android",
        )
    return f"Bearer {issue_tokens(device).access}"


def in_days(days, hour=9):
    today = datetime.now(ABIDJAN).date()
    local = datetime(today.year, today.month, today.day, hour, tzinfo=ABIDJAN) + timedelta(days=days)
    return local.astimezone(UTC)


@pytest.fixture
def jobber(enrolled):
    return enrolled.device.user


@pytest.fixture
def author(verified_householder):
    return verified_householder


def make(author, status, days=2, **overrides):
    category = OfferCategory.objects.get(name="Ménage")
    values = {
        "author": author,
        "category": category,
        "category_name": "Ménage",
        "duties": ["Dépoussiérer"],
        "starts_at": in_days(days),
        "duration_minutes": 180,
        "pay_xof": 3000,
        "note": "Merci d'apporter des gants.",
        "commune": "Cocody",
        "quartier": "Angré",
        "status": status,
        "sent_at": timezone.now(),
        "published_at": timezone.now() if status == "published" else None,
    }
    values.update(overrides)
    return Offer.objects.create(**values)


def test_jobber_sees_only_published_future_offers_soonest_first(api_client, jobber, author):
    later = make(author, "published", days=5)
    sooner = make(author, "published", days=2)
    for status in ("draft", "in_review", "refused", "withdrawn", "closed"):
        make(author, status, days=3)
    make(author, "published", days=-1)  # already started
    response = api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer_for_user(jobber))
    assert response.status_code == 200
    assert [o["id"] for o in response.json()["results"]] == [str(sooner.pk), str(later.pk)]


def test_public_offer_has_exactly_the_allowed_keys(api_client, jobber, author):
    make(author, "published")
    item = api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer_for_user(jobber)).json()["results"][0]
    assert set(item) == PUBLIC_KEYS
    assert item["commune"] == "Cocody" and item["quartier"] == "Angré"


def test_no_response_contains_address_position_phone_or_author(api_client, jobber, author):
    offer = make(author, "published", flags=["travel"], reason="Motif interne")
    bearer = bearer_for_user(jobber)
    texts = [
        api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer).content.decode(),
        api_client.get(f"{BASE}/{offer.pk}", HTTP_AUTHORIZATION=bearer).content.decode(),
    ]
    for text in texts:
        for secret in (
            author.phone,
            str(author.pk),
            "5.3599",
            "3.9871",
            "flags",
            "travel",
            "Motif interne",
            "reason",
            "author",
            "pay_high",
            "Kouassi",
        ):
            assert secret not in text, secret


def test_commune_filter_and_unknown_commune(api_client, jobber, author):
    make(author, "published", days=2)
    make(author, "published", days=3, commune="Yopougon", quartier="Niangon")
    bearer = bearer_for_user(jobber)
    everyone = api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer).json()
    assert everyone["count"] == 2
    assert "Cocody" in everyone["communes"] and len(everyone["communes"]) == 13
    only = api_client.get(f"{BASE}?commune=Yopougon", HTTP_AUTHORIZATION=bearer).json()
    assert [o["commune"] for o in only["results"]] == ["Yopougon"]
    bad = api_client.get(f"{BASE}?commune=Paris", HTTP_AUTHORIZATION=bearer)
    assert bad.status_code == 400 and bad.json()["error"] == "commune_invalid"


@pytest.mark.parametrize("status", ["draft", "in_review", "refused", "withdrawn", "closed"])
def test_detail_of_a_hidden_offer_is_404(api_client, jobber, author, status):
    offer = make(author, status)
    response = api_client.get(f"{BASE}/{offer.pk}", HTTP_AUTHORIZATION=bearer_for_user(jobber))
    assert response.status_code == 404


def test_detail_of_a_past_published_offer_is_404(api_client, jobber, author):
    offer = make(author, "published", days=-1)  # Review Focus 3: before the periodic task runs
    assert api_client.get(f"{BASE}/{offer.pk}", HTTP_AUTHORIZATION=bearer_for_user(jobber)).status_code == 404


def test_pagination_is_20_per_page(api_client, jobber, author):
    for day in range(2, 26):
        make(author, "published", days=day)
    bearer = bearer_for_user(jobber)
    first = api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer).json()
    second = api_client.get(f"{BASE}?page=2", HTTP_AUTHORIZATION=bearer).json()
    assert first["count"] == 24 and len(first["results"]) == 20 and first["next"] is not None
    assert len(second["results"]) == 4 and second["next"] is None


def test_householder_staff_and_anonymous_are_refused(api_client, author, staff_user, make_device):
    assert api_client.get(f"{BASE}").status_code == 401
    assert api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer_for_user(author)).status_code == 403
    staff_device = make_device(staff_user)
    assert api_client.get(f"{BASE}", HTTP_AUTHORIZATION=bearer_for_user(staff_device.user)).status_code == 403


def test_detail_of_a_visible_offer_is_200(api_client, jobber, author):
    # Control for the 404 tests above: a visible offer is found at the same address.
    offer = make(author, "published", days=2)
    response = api_client.get(f"{BASE}/{offer.pk}", HTTP_AUTHORIZATION=bearer_for_user(jobber))
    assert response.status_code == 200 and set(response.json()) == PUBLIC_KEYS
