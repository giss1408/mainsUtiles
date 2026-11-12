import uuid

import pytest

from apps.accounts.models import DeviceEnrolmentRequest
from apps.accounts.services.enrolment import approve, hold, issue_code, refuse

URL = "/api/v1/enrolment/applications"
TOKEN = {"HTTP_X_ENROLMENT_TOKEN": "tok"}

pytestmark = pytest.mark.django_db


def row(created):
    return DeviceEnrolmentRequest.objects.get(pk=created["id"])


def test_create_returns_201_pending_with_response_hours(api_client, payload):
    r = api_client.post(URL, payload, format="json")
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "pending" and body["response_hours"] == 24
    assert body["kind"] == "new_account" and body["reason"] == ""
    assert set(body) == {"id", "status", "kind", "reason", "response_hours"}
    assert row(body).phone == "+2250708091011"


def test_repeat_create_returns_200_same_id(api_client, payload, created):
    r = api_client.post(URL, payload, format="json")
    assert r.status_code == 200 and r.json()["id"] == created["id"]


def test_staff_role_and_bad_public_key_are_rejected_400(api_client, payload):
    assert api_client.post(URL, {**payload, "role": "staff"}, format="json").status_code == 400
    assert api_client.post(URL, {**payload, "public_key": "c2hvcnQ="}, format="json").status_code == 400
    assert api_client.post(URL, {**payload, "public_key": "not base64!"}, format="json").status_code == 400
    assert DeviceEnrolmentRequest.objects.count() == 0


def test_invalid_phone_is_400_with_french_message(api_client, payload):
    r = api_client.post(URL, {**payload, "phone": "12345"}, format="json")
    assert r.status_code == 400
    assert r.json() == {"error": "invalid_phone", "message": "Numéro de téléphone invalide."}


def test_status_requires_matching_token_else_404(api_client, created):
    assert api_client.get(f"{URL}/{created['id']}", **TOKEN).status_code == 200
    assert api_client.get(f"{URL}/{created['id']}", HTTP_X_ENROLMENT_TOKEN="other").status_code == 404
    assert api_client.get(f"{URL}/{created['id']}").status_code == 404
    assert api_client.get(f"{URL}/{uuid.uuid4()}", **TOKEN).status_code == 404


def test_approved_is_shown_as_pending_and_code_sent_as_awaiting_code(api_client, created, staff_user):
    req = row(created)
    approve(req, staff=staff_user)
    assert api_client.get(f"{URL}/{req.id}", **TOKEN).json()["status"] == "pending"
    issue_code(req, staff=staff_user)
    assert api_client.get(f"{URL}/{req.id}", **TOKEN).json()["status"] == "awaiting_code"


def test_confirm_success_returns_device_id(api_client, created, staff_user, device_key):
    req = row(created)
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    r = api_client.post(f"{URL}/{req.id}/confirm", {"code": code}, format="json", **TOKEN)
    assert r.status_code == 200
    assert r.json() == {"status": "completed", "device_id": device_key.device_id}
    assert api_client.get(f"{URL}/{req.id}", **TOKEN).json()["status"] == "completed"


def test_wrong_code_is_422_with_french_message(api_client, created, staff_user):
    req = row(created)
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    bad = "000000" if code != "000000" else "111111"
    r = api_client.post(f"{URL}/{req.id}/confirm", {"code": bad}, format="json", **TOKEN)
    assert r.status_code == 422
    assert r.json() == {"error": "code_invalid", "message": "Numéro de confirmation incorrect."}


def test_confirm_with_wrong_token_is_404_and_before_send_is_409(api_client, created):
    url = f"{URL}/{created['id']}/confirm"
    r = api_client.post(url, {"code": "123456"}, format="json", HTTP_X_ENROLMENT_TOKEN="other")
    assert r.status_code == 404
    r = api_client.post(url, {"code": "123456"}, format="json", **TOKEN)
    assert r.status_code == 409 and r.json()["error"] == "invalid_state"


def test_fifth_wrong_code_is_423_locked(api_client, created, staff_user):
    req = row(created)
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    bad = "000000" if code != "000000" else "111111"
    for _ in range(4):
        api_client.post(f"{URL}/{req.id}/confirm", {"code": bad}, format="json", **TOKEN)
    r = api_client.post(f"{URL}/{req.id}/confirm", {"code": bad}, format="json", **TOKEN)
    assert r.status_code == 423
    assert r.json() == {"error": "locked", "message": "Trop d'essais. Faites une nouvelle demande."}


def test_rate_limit_is_429(api_client, payload):
    for _ in range(3):
        body = {**payload, "device_id": str(uuid.uuid4())}
        assert api_client.post(URL, body, format="json").status_code == 201
    r = api_client.post(URL, {**payload, "device_id": str(uuid.uuid4())}, format="json")
    assert r.status_code == 429
    assert r.json() == {"error": "rate_limited", "message": "Trop de demandes. Réessayez demain."}


def test_refused_and_held_applications_show_reason(api_client, created, staff_user):
    req = row(created)
    hold(req, staff=staff_user, reason="Vérification en cours")
    body = api_client.get(f"{URL}/{req.id}", **TOKEN).json()
    assert (body["status"], body["reason"]) == ("held", "Vérification en cours")
    refuse(req, staff=staff_user, reason="Numéro injoignable")
    body = api_client.get(f"{URL}/{req.id}", **TOKEN).json()
    assert (body["status"], body["reason"]) == ("refused", "Numéro injoignable")


def test_client_ip_is_recorded(api_client, payload):
    r = api_client.post(URL, payload, format="json", REMOTE_ADDR="41.66.1.2")
    assert row(r.json()).ip_address == "41.66.1.2"


def test_schema_lists_the_three_enrolment_paths(api_client):
    paths = api_client.get("/api/schema/?format=json").json()["paths"]
    assert {
        "/api/v1/enrolment/applications",
        "/api/v1/enrolment/applications/{id}",
        "/api/v1/enrolment/applications/{id}/confirm",
    } <= set(paths)
