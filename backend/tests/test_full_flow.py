import pytest

from apps.accounts.models import Device, DeviceEnrolmentRequest
from apps.accounts.services.enrolment import approve, issue_code

pytestmark = pytest.mark.django_db


def test_apply_approve_send_confirm_sign_in(api_client, payload, device_key, staff_user):
    token = {"HTTP_X_ENROLMENT_TOKEN": "tok"}
    created = api_client.post("/api/v1/enrolment/applications", payload, format="json").json()
    url = f"/api/v1/enrolment/applications/{created['id']}"
    assert api_client.get(url, **token).json()["status"] == "pending"

    req = DeviceEnrolmentRequest.objects.get(pk=created["id"])
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    assert api_client.get(url, **token).json()["status"] == "awaiting_code"

    confirmed = api_client.post(f"{url}/confirm", {"code": code}, format="json", **token)
    assert confirmed.status_code == 200

    nonce = api_client.post(
        "/api/v1/auth/challenge", {"device_id": device_key.device_id}, format="json"
    ).json()["nonce"]
    tokens = api_client.post(
        "/api/v1/auth/token",
        {
            "device_id": device_key.device_id,
            "nonce": nonce,
            "signature": device_key.sign(f"petitgombo-auth:{device_key.device_id}:{nonce}"),
        },
        format="json",
    ).json()
    me = api_client.get("/api/v1/me", HTTP_AUTHORIZATION=f"Bearer {tokens['access']}").json()

    assert me["phone"] == "+2250708091011" and me["role"] == "jobber"
    assert me["device_id"] == device_key.device_id
    assert Device.objects.filter(status="active").count() == 1
