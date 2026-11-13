import json
import uuid

import pytest

from apps.verification.models import BriefingCard, TrustedContact
from apps.verification.services import contacts

pytestmark = pytest.mark.django_db

BASE = "/api/v1/jobber/verification"
PHONE_A, PHONE_B = "07 07 07 07 07", "01 01 01 01 01"


@pytest.fixture
def jobber_bearer(enrolled, bearer_for):
    return bearer_for(enrolled.device)


@pytest.fixture
def auth(jobber_bearer):
    return {"HTTP_AUTHORIZATION": jobber_bearer}


def new_contact(api_client, auth, phone=PHONE_A, name="Awa Koné", relationship="parent"):
    return api_client.post(
        f"{BASE}/contacts",
        {"name": name, "phone": phone, "relationship": relationship},
        format="json",
        **auth,
    )


def confirmed(api_client, auth, verifier, phone=PHONE_A):
    body = new_contact(api_client, auth, phone).json()
    sent = contacts.send_code(TrustedContact.objects.get(pk=body["id"]), staff=verifier)
    response = api_client.post(f"{BASE}/contacts/{body['id']}/confirm", {"code": sent}, format="json", **auth)
    assert response.status_code == 200
    return response.json()


def test_contact_roundtrip_add_staff_sends_confirm_replace_confirm_list(api_client, auth, verifier):
    created = new_contact(api_client, auth)
    assert created.status_code == 201
    body = created.json()
    assert body["status"] == "pending" and body["awaiting_code"] is True and body["replaces"] is None
    assert set(body) == {"id", "name", "relationship", "status", "replaces", "awaiting_code", "ends_at"}

    listing = api_client.get(f"{BASE}/contacts", **auth).json()
    assert listing["max"] == 2 and [c["id"] for c in listing["contacts"]] == [body["id"]]

    sent = contacts.send_code(TrustedContact.objects.get(pk=body["id"]), staff=verifier)
    done = api_client.post(f"{BASE}/contacts/{body['id']}/confirm", {"code": sent}, format="json", **auth)
    assert done.status_code == 200 and done.json()["status"] == "confirmed"

    swap = api_client.post(
        f"{BASE}/contacts/{body['id']}/replace",
        {"name": "Yao", "phone": PHONE_B, "relationship": "friend"},
        format="json",
        **auth,
    )
    assert swap.status_code == 201 and swap.json()["replaces"] == body["id"]
    listing = api_client.get(f"{BASE}/contacts", **auth).json()
    assert [c["status"] for c in listing["contacts"]] == ["confirmed", "pending"]
    sent = contacts.send_code(TrustedContact.objects.get(pk=swap.json()["id"]), staff=verifier)
    again = api_client.post(
        f"{BASE}/contacts/{swap.json()['id']}/confirm", {"code": sent}, format="json", **auth
    )
    assert again.status_code == 200
    checklist = api_client.get(BASE, **auth).json()
    assert checklist["trusted_contact"]["confirmed"] == 2


def test_the_contact_route_has_no_delete(api_client, auth):
    body = new_contact(api_client, auth).json()
    assert api_client.get(f"{BASE}/contacts/{body['id']}", **auth).status_code == 200
    assert api_client.delete(f"{BASE}/contacts/{body['id']}", **auth).status_code == 405


def endpoints():
    some = uuid.uuid4()
    return [
        ("get", f"{BASE}/contacts", None),
        ("post", f"{BASE}/contacts", {"name": "A", "phone": PHONE_A, "relationship": "parent"}),
        ("get", f"{BASE}/contacts/{some}", None),
        ("post", f"{BASE}/contacts/{some}/code", {}),
        ("post", f"{BASE}/contacts/{some}/confirm", {"code": "123456"}),
        (
            "post",
            f"{BASE}/contacts/{some}/replace",
            {"name": "A", "phone": PHONE_A, "relationship": "parent"},
        ),
        ("get", f"{BASE}/briefing", None),
        ("post", f"{BASE}/briefing/{some}/answer", {"choice": 0}),
    ]


def statuses(api_client, bearer=None):
    extra = {"HTTP_AUTHORIZATION": bearer} if bearer else {}
    return [
        getattr(api_client, method)(url, body, format="json", **extra).status_code
        for method, url, body in endpoints()
    ]


def test_anonymous_gets_401_on_every_new_endpoint(api_client):
    assert statuses(api_client) == [401] * 8


def test_householder_and_staff_tokens_get_403_on_every_new_endpoint(
    api_client, householder_bearer, staff_user, make_device, bearer_for
):
    assert statuses(api_client, householder_bearer) == [403] * 8
    assert statuses(api_client, bearer_for(make_device(staff_user))) == [403] * 8
    assert not TrustedContact.objects.exists()


def test_one_jobber_cannot_see_or_touch_anothers_contact(api_client, auth, enrol_device, bearer_for):
    body = new_contact(api_client, auth).json()
    other = {"HTTP_AUTHORIZATION": bearer_for(enrol_device(phone="0509090909", role="jobber").device)}
    for method, suffix, data in [
        ("get", "", None),
        ("post", "/code", {}),
        ("post", "/confirm", {"code": "123456"}),
        ("post", "/replace", {"name": "A", "phone": PHONE_B, "relationship": "parent"}),
    ]:
        response = getattr(api_client, method)(
            f"{BASE}/contacts/{body['id']}{suffix}", data, format="json", **other
        )
        assert response.status_code == 404 and response.json()["error"] == "forbidden"
    assert api_client.get(f"{BASE}/contacts", **other).json()["contacts"] == []


def test_no_response_contains_a_phone_a_code_or_the_answer_key(api_client, auth, verifier):
    texts = []
    created = new_contact(api_client, auth)
    texts.append(created.content.decode())
    body = created.json()
    sent = contacts.send_code(TrustedContact.objects.get(pk=body["id"]), staff=verifier)
    texts.append(
        api_client.post(
            f"{BASE}/contacts/{body['id']}/confirm", {"code": sent}, format="json", **auth
        ).content.decode()
    )
    texts.append(api_client.get(f"{BASE}/contacts", **auth).content.decode())
    texts.append(api_client.get(BASE, **auth).content.decode())
    briefing = api_client.get(f"{BASE}/briefing", **auth)
    texts.append(briefing.content.decode())
    card = briefing.json()["cards"][0]
    texts.append(
        api_client.post(
            f"{BASE}/briefing/{card['id']}/answer", {"choice": 0}, format="json", **auth
        ).content.decode()
    )
    everything = "".join(texts)
    for secret in ("0707070707", "+225070707", sent, "correct_index"):
        assert secret not in everything


def test_error_codes_map_to_status_and_message(api_client, auth, verifier):
    def error(response, status, code):
        body = response.json()
        assert (response.status_code, body["error"]) == (status, code) and body["message"]

    error(new_contact(api_client, auth, phone="123"), 400, "contact_phone_invalid")
    error(new_contact(api_client, auth, name=" "), 400, "contact_name_required")
    error(new_contact(api_client, auth, relationship="boss"), 400, "relationship_invalid")
    error(new_contact(api_client, auth, phone="0708091011"), 400, "contact_phone_own")
    first = new_contact(api_client, auth).json()
    error(new_contact(api_client, auth, phone="0707070707"), 400, "contact_phone_duplicate")
    error(
        api_client.post(f"{BASE}/contacts/{first['id']}/code", {}, format="json", **auth),
        429,
        "contact_code_wait",
    )
    error(
        api_client.post(f"{BASE}/contacts/{first['id']}/confirm", {"code": "123456"}, format="json", **auth),
        422,
        "contact_code_expired",
    )
    sent = contacts.send_code(TrustedContact.objects.get(pk=first["id"]), staff=verifier)
    wrong = "000000" if sent != "000000" else "111111"
    for _ in range(5):
        error(
            api_client.post(f"{BASE}/contacts/{first['id']}/confirm", {"code": wrong}, format="json", **auth),
            422,
            "contact_code_invalid",
        )
    error(
        api_client.post(f"{BASE}/contacts/{first['id']}/confirm", {"code": sent}, format="json", **auth),
        423,
        "contact_locked",
    )
    new_contact(api_client, auth, phone=PHONE_B)
    error(new_contact(api_client, auth, phone="0102030405"), 409, "contact_limit")
    error(
        api_client.post(f"{BASE}/briefing/{uuid.uuid4()}/answer", {"choice": 0}, format="json", **auth),
        400,
        "card_invalid",
    )
    card = BriefingCard.objects.first()
    error(
        api_client.post(f"{BASE}/briefing/{card.pk}/answer", {"choice": 9}, format="json", **auth),
        400,
        "choice_invalid",
    )


def test_briefing_flow_to_complete_then_checklist_confirmed(api_client, auth):
    body = api_client.get(f"{BASE}/briefing", **auth).json()
    assert body["progress"]["status"] == "not_started" and len(body["cards"]) == 3
    for card in body["cards"]:
        correct = BriefingCard.objects.get(pk=card["id"]).correct_index
        result = api_client.post(
            f"{BASE}/briefing/{card['id']}/answer", {"choice": correct}, format="json", **auth
        ).json()
        assert result["correct"] is True
    assert result["complete"] is True
    assert api_client.get(BASE, **auth).json()["briefing"]["status"] == "confirmed"


def test_wrong_answer_is_200_with_correct_false(api_client, auth):
    card = api_client.get(f"{BASE}/briefing", **auth).json()["cards"][0]
    wrong = (BriefingCard.objects.get(pk=card["id"]).correct_index + 1) % 3
    response = api_client.post(
        f"{BASE}/briefing/{card['id']}/answer", {"choice": wrong}, format="json", **auth
    )
    body = response.json()
    assert response.status_code == 200 and body["correct"] is False and body["explanation"]
    assert set(body) == {"correct", "explanation", "complete"}
    json.dumps(body)
