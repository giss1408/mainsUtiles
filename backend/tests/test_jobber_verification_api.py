import json

import pytest

from apps.verification.models import Guarantor, Status
from tests.test_verification_api import BASE as HOUSEHOLDER_BASE
from tests.test_verification_api import NOW, identity_body, upload

pytestmark = pytest.mark.django_db

BASE = "/api/v1/jobber/verification"


def guarantor_body(jpeg, **overrides):
    body = {
        "document_type": "facture_eau",
        "photo": upload(jpeg(40)),
        "guarantor_name": "Kouassi Yao",
        "guarantor_phone": "07 07 07 07 07",
        "relationship": "parent",
        "captured_at": NOW,
    }
    body.update(overrides)
    return body


@pytest.fixture
def jobber_bearer(enrolled, bearer_for):
    return bearer_for(enrolled.device)


def calls(api_client, jpeg, bearer=None):
    auth = {"HTTP_AUTHORIZATION": bearer} if bearer else {}
    return [
        api_client.get(BASE, **auth),
        api_client.post(f"{BASE}/identity", identity_body(jpeg), format="multipart", **auth),
        api_client.post(f"{BASE}/guarantor", guarantor_body(jpeg), format="multipart", **auth),
    ]


def test_every_endpoint_needs_a_token(api_client, jpeg):
    assert [r.status_code for r in calls(api_client, jpeg)] == [401] * 3


def test_householder_and_staff_tokens_get_403_on_every_jobber_endpoint(
    api_client, jpeg, householder_bearer, staff_user, make_device, bearer_for
):
    assert [r.status_code for r in calls(api_client, jpeg, householder_bearer)] == [403] * 3
    assert [r.status_code for r in calls(api_client, jpeg, bearer_for(make_device(staff_user)))] == [403] * 3
    assert not Guarantor.objects.exists()


def test_jobber_token_gets_403_on_householder_endpoints(api_client, jobber_bearer):
    response = api_client.get(HOUSEHOLDER_BASE, HTTP_AUTHORIZATION=jobber_bearer)
    assert response.status_code == 403


def test_checklist_for_a_new_jobber(api_client, jobber_bearer):
    response = api_client.get(BASE, HTTP_AUTHORIZATION=jobber_bearer)
    assert response.status_code == 200
    assert response.json() == {
        "tier": "J0",
        "review_hours": 24,
        "required": ["identity", "guarantor"],
        "identity": {"status": "not_started", "reason": ""},
        "guarantor": {"status": "not_started", "reason": ""},
    }


def test_identity_then_guarantor_roundtrip(api_client, jobber_bearer, jpeg):
    first = api_client.post(
        f"{BASE}/identity", identity_body(jpeg), format="multipart", HTTP_AUTHORIZATION=jobber_bearer
    )
    second = api_client.post(
        f"{BASE}/guarantor",
        guarantor_body(jpeg),
        format="multipart",
        HTTP_AUTHORIZATION=jobber_bearer,
    )
    assert (first.status_code, second.status_code) == (201, 201)
    body = second.json()
    assert body["identity"]["status"] == "submitted" and body["guarantor"]["status"] == "submitted"
    assert body["tier"] == "J0"


def test_the_response_never_contains_guarantor_data_or_storage_names(api_client, jobber_bearer, jpeg):
    response = api_client.post(
        f"{BASE}/guarantor",
        guarantor_body(jpeg),
        format="multipart",
        HTTP_AUTHORIZATION=jobber_bearer,
    )
    text = json.dumps(response.json()) + response.content.decode()
    record = Guarantor.objects.get()
    for secret in ("Kouassi", "0707070707", "+2250707070707", record.photo.storage_name):
        assert secret not in text


@pytest.mark.parametrize(
    ("overrides", "status", "code"),
    [
        ({"guarantor_phone": "12345"}, 400, "guarantor_phone_invalid"),
        ({"guarantor_phone": "0708091011"}, 400, "guarantor_phone_own"),
        ({"guarantor_name": "  "}, 400, "guarantor_name_required"),
        ({"relationship": "friend"}, 400, "relationship_invalid"),
        ({"document_type": "cni"}, 400, "document_type_invalid"),
    ],
)
def test_error_codes_map_to_a_status_and_a_french_message(
    api_client, jobber_bearer, jpeg, overrides, status, code
):
    response = api_client.post(
        f"{BASE}/guarantor",
        guarantor_body(jpeg, **overrides),
        format="multipart",
        HTTP_AUTHORIZATION=jobber_bearer,
    )
    assert response.status_code == status
    assert response.json()["error"] == code and response.json()["message"]


def test_a_missing_field_is_400(api_client, jobber_bearer, jpeg):
    body = guarantor_body(jpeg)
    del body["guarantor_name"]
    response = api_client.post(
        f"{BASE}/guarantor", body, format="multipart", HTTP_AUTHORIZATION=jobber_bearer
    )
    assert response.status_code == 400


def test_sending_twice_is_409(api_client, jobber_bearer, jpeg):
    for expected in (201, 409):
        response = api_client.post(
            f"{BASE}/guarantor",
            guarantor_body(jpeg),
            format="multipart",
            HTTP_AUTHORIZATION=jobber_bearer,
        )
        assert response.status_code == expected


def test_an_oversized_photo_is_413(api_client, jobber_bearer, jpeg, settings):
    settings.VERIFICATION_PHOTO_MAX_BYTES = 100
    response = api_client.post(
        f"{BASE}/guarantor",
        guarantor_body(jpeg, photo=upload(jpeg(1, size=500))),
        format="multipart",
        HTTP_AUTHORIZATION=jobber_bearer,
    )
    assert response.status_code == 413


def test_one_jobber_never_sees_anothers_state(api_client, jobber_bearer, jpeg, enrol_device, bearer_for):
    api_client.post(
        f"{BASE}/guarantor",
        guarantor_body(jpeg),
        format="multipart",
        HTTP_AUTHORIZATION=jobber_bearer,
    )
    other = enrol_device(phone="0101010101", role="jobber")
    response = api_client.get(BASE, HTTP_AUTHORIZATION=bearer_for(other.device))
    assert response.json()["guarantor"]["status"] == "not_started"
    assert Guarantor.objects.filter(status=Status.SUBMITTED).count() == 1
