import io

import pytest
from django.utils import timezone

from apps.verification.models import IdentityVerification, Status

pytestmark = pytest.mark.django_db

BASE = "/api/v1/verification"
NOW = timezone.now().isoformat()


def upload(data: bytes, name="photo.jpg"):
    file = io.BytesIO(data)
    file.name = name
    return file


def identity_body(jpeg, **overrides):
    body = {
        "document_type": "cni",
        "front": upload(jpeg(0)),
        "back": upload(jpeg(1)),
        "selfie": upload(jpeg(2)),
        "captured_at": NOW,
    }
    body.update(overrides)
    return {k: v for k, v in body.items() if v is not None}


def address_body(jpeg, **overrides):
    body = {
        "document_type": "facture_electricite",
        "photo": upload(jpeg(10)),
        "commune": "Yopougon",
        "quartier": "Niangon Nord",
        "captured_at": NOW,
    }
    body.update(overrides)
    return body


LOCATION = {"lat": 5.3599, "lng": -3.9871, "accuracy_m": 12.4, "mock_location": False, "captured_at": NOW}


def calls(api_client, jpeg, bearer=None):
    """Every endpoint called once, with a valid body."""
    auth = {"HTTP_AUTHORIZATION": bearer} if bearer else {}
    return [
        api_client.get(BASE, **auth),
        api_client.post(f"{BASE}/identity", identity_body(jpeg), format="multipart", **auth),
        api_client.post(f"{BASE}/address", address_body(jpeg), format="multipart", **auth),
        api_client.post(f"{BASE}/home-location", LOCATION, format="json", **auth),
    ]


def test_every_endpoint_needs_a_token(api_client, jpeg):
    assert [r.status_code for r in calls(api_client, jpeg)] == [401] * 4


def test_jobber_and_staff_tokens_get_403_everywhere(
    api_client, jpeg, enrolled, staff_user, make_device, bearer_for
):
    for device in (enrolled.device, make_device(staff_user)):
        assert [r.status_code for r in calls(api_client, jpeg, bearer_for(device))] == [403] * 4
    assert not IdentityVerification.objects.exists()


def test_new_householder_sees_empty_checklist_with_communes(api_client, householder_bearer):
    r = api_client.get(BASE, HTTP_AUTHORIZATION=householder_bearer)
    assert r.status_code == 200
    body = r.json()
    assert body["tier"] == "H0" and body["review_hours"] == 24
    assert "Cocody" in body["communes"] and len(body["communes"]) == 13
    assert body["identity"] == {"status": "not_started", "reason": ""}


def test_identity_upload_returns_checklist_with_submitted(api_client, householder_bearer, householder, jpeg):
    body = identity_body(jpeg, lat="5.36", lng="-3.98")
    r = api_client.post(f"{BASE}/identity", body, format="multipart", HTTP_AUTHORIZATION=householder_bearer)
    assert r.status_code == 201, r.content
    assert r.json()["identity"] == {"status": "submitted", "reason": ""}
    record = IdentityVerification.objects.get(user=householder)
    assert record.front.capture_position != ""


def test_identity_upload_twice_is_409(api_client, householder_bearer, jpeg):
    post = lambda: api_client.post(  # noqa: E731
        f"{BASE}/identity", identity_body(jpeg), format="multipart", HTTP_AUTHORIZATION=householder_bearer
    )
    assert post().status_code == 201
    again = post()
    assert again.status_code == 409
    assert again.json() == {"error": "invalid_state", "message": "Cette étape est déjà envoyée."}


def test_missing_selfie_or_bad_document_type_is_400(api_client, householder_bearer, jpeg):
    r = api_client.post(
        f"{BASE}/identity",
        identity_body(jpeg, selfie=None),
        format="multipart",
        HTTP_AUTHORIZATION=householder_bearer,
    )
    assert r.status_code == 400
    r = api_client.post(
        f"{BASE}/identity",
        identity_body(jpeg, document_type="library_card"),
        format="multipart",
        HTTP_AUTHORIZATION=householder_bearer,
    )
    assert r.status_code == 400 and r.json()["error"] == "document_type_invalid"
    assert not IdentityVerification.objects.exists()


def test_oversized_photo_is_413_and_not_a_photo_is_400(api_client, householder_bearer, jpeg, settings):
    r = api_client.post(
        f"{BASE}/address",
        address_body(jpeg, photo=upload(b"plain text")),
        format="multipart",
        HTTP_AUTHORIZATION=householder_bearer,
    )
    assert r.status_code == 400
    assert r.json() == {"error": "photo_invalid", "message": "Photo illisible. Reprenez la photo."}

    settings.VERIFICATION_PHOTO_MAX_BYTES = 100
    r = api_client.post(
        f"{BASE}/address", address_body(jpeg), format="multipart", HTTP_AUTHORIZATION=householder_bearer
    )
    assert r.status_code == 413 and r.json()["error"] == "photo_too_large"


def test_address_upload_then_checklist_shows_commune_and_quartier(api_client, householder_bearer, jpeg):
    r = api_client.post(
        f"{BASE}/address", address_body(jpeg), format="multipart", HTTP_AUTHORIZATION=householder_bearer
    )
    assert r.status_code == 201, r.content
    address = api_client.get(BASE, HTTP_AUTHORIZATION=householder_bearer).json()["address"]
    assert address == {
        "status": "submitted",
        "reason": "",
        "commune": "Yopougon",
        "quartier": "Niangon Nord",
        "expires_at": None,
    }


def test_unknown_commune_is_400_with_french_message(api_client, householder_bearer, jpeg):
    r = api_client.post(
        f"{BASE}/address",
        address_body(jpeg, commune="Paris"),
        format="multipart",
        HTTP_AUTHORIZATION=householder_bearer,
    )
    assert r.status_code == 400
    assert r.json() == {"error": "commune_invalid", "message": "Commune non desservie."}


def test_home_location_recorded_and_inaccurate_is_422(api_client, householder_bearer):
    bad = api_client.post(
        f"{BASE}/home-location",
        LOCATION | {"accuracy_m": 180},
        format="json",
        HTTP_AUTHORIZATION=householder_bearer,
    )
    assert bad.status_code == 422 and bad.json()["error"] == "location_inaccurate"
    assert "Position trop imprécise" in bad.json()["message"]

    ok = api_client.post(
        f"{BASE}/home-location", LOCATION, format="json", HTTP_AUTHORIZATION=householder_bearer
    )
    assert ok.status_code == 201 and ok.json()["home_location"]["status"] == "submitted"
    out_of_range = api_client.post(
        f"{BASE}/home-location", LOCATION | {"lat": 123}, format="json", HTTP_AUTHORIZATION=householder_bearer
    )
    assert out_of_range.status_code == 400


def test_response_never_contains_storage_names_or_coordinates(api_client, householder_bearer, jpeg):
    responses = calls(api_client, jpeg, householder_bearer)
    assert [r.status_code for r in responses] == [200, 201, 201, 201]
    for r in responses + [api_client.get(BASE, HTTP_AUTHORIZATION=householder_bearer)]:
        text = r.content.decode()
        assert ".bin" not in text and "5.3599" not in text and "3.9871" not in text


def test_one_householder_never_sees_anothers_status(
    api_client, householder_bearer, householder, enrol_device, bearer_for, jpeg
):
    api_client.post(
        f"{BASE}/identity", identity_body(jpeg), format="multipart", HTTP_AUTHORIZATION=householder_bearer
    )
    IdentityVerification.objects.filter(user=householder).update(status=Status.REFUSED, reason="Photo floue")

    other = enrol_device(phone="0101010102", role="householder")
    body = api_client.get(BASE, HTTP_AUTHORIZATION=bearer_for(other.device)).json()
    assert body["identity"] == {"status": "not_started", "reason": ""}
    mine = api_client.get(BASE, HTTP_AUTHORIZATION=householder_bearer).json()
    assert mine["identity"] == {"status": "refused", "reason": "Photo floue"}
