from datetime import timedelta

import pytest
from freezegun import freeze_time
from rest_framework.test import APIRequestFactory

from apps.accounts.models import RefreshToken, User
from apps.accounts.permissions import IsHouseholder, IsJobber
from tests.helpers import DeviceKey

pytestmark = pytest.mark.django_db


def challenge(api_client, device_id):
    return api_client.post("/api/v1/auth/challenge", {"device_id": device_id}, format="json").json()["nonce"]


def token_call(api_client, key, nonce, signer=None):
    signer = signer or key
    signature = signer.sign(f"petitgombo-auth:{key.device_id}:{nonce}")
    body = {"device_id": key.device_id, "nonce": nonce, "signature": signature}
    return api_client.post("/api/v1/auth/token", body, format="json")


def sign_in(api_client, key):
    response = token_call(api_client, key, challenge(api_client, key.device_id))
    assert response.status_code == 200, response.content
    return response.json()


def me(api_client, access):
    return api_client.get("/api/v1/me", HTTP_AUTHORIZATION=f"Bearer {access}")


def test_sign_in_with_valid_signature_returns_tokens_and_me_works(api_client, enrolled):
    tokens = sign_in(api_client, enrolled)
    body = me(api_client, tokens["access"]).json()
    assert body["phone"] == "+2250708091011" and body["role"] == "jobber"
    assert body["device_id"] == enrolled.device_id
    assert set(tokens) == {"access", "refresh"}


def test_nonce_cannot_be_reused(api_client, enrolled):
    nonce = challenge(api_client, enrolled.device_id)
    assert token_call(api_client, enrolled, nonce).status_code == 200
    again = token_call(api_client, enrolled, nonce)
    assert again.status_code == 401 and again.json() == {"error": "challenge_invalid"}


def test_signature_from_another_key_is_rejected(api_client, enrolled):
    nonce = challenge(api_client, enrolled.device_id)
    r = token_call(api_client, enrolled, nonce, signer=DeviceKey())
    assert r.status_code == 401 and r.json() == {"error": "signature_invalid"}


def test_malformed_signature_is_rejected(api_client, enrolled):
    nonce = challenge(api_client, enrolled.device_id)
    body = {"device_id": enrolled.device_id, "nonce": nonce, "signature": "not-base64!"}
    r = api_client.post("/api/v1/auth/token", body, format="json")
    assert r.status_code == 401 and r.json() == {"error": "signature_invalid"}


def test_expired_challenge_is_rejected(api_client, enrolled):
    with freeze_time("2026-11-12 10:00:00") as clock:
        nonce = challenge(api_client, enrolled.device_id)
        clock.tick(timedelta(seconds=121))
        r = token_call(api_client, enrolled, nonce)
    assert r.status_code == 401 and r.json() == {"error": "challenge_invalid"}


def test_expired_access_token_is_401(api_client, enrolled):
    with freeze_time("2026-11-12 10:00:00") as clock:
        tokens = sign_in(api_client, enrolled)
        assert me(api_client, tokens["access"]).status_code == 200
        clock.tick(timedelta(minutes=16))
        assert me(api_client, tokens["access"]).status_code == 401


def test_refresh_rotates_and_old_refresh_revokes_family(api_client, enrolled):
    first = sign_in(api_client, enrolled)
    second = api_client.post("/api/v1/auth/refresh", {"refresh": first["refresh"]}, format="json")
    assert second.status_code == 200
    assert second.json()["refresh"] != first["refresh"]
    assert me(api_client, second.json()["access"]).status_code == 200

    replay = api_client.post("/api/v1/auth/refresh", {"refresh": first["refresh"]}, format="json")
    assert replay.status_code == 401 and replay.json() == {"error": "refresh_invalid"}
    # The stolen-token signal revokes the newest token as well.
    after = api_client.post("/api/v1/auth/refresh", {"refresh": second.json()["refresh"]}, format="json")
    assert after.status_code == 401
    assert not RefreshToken.objects.filter(revoked_at__isnull=True).exists()


def test_refresh_tokens_are_stored_hashed(api_client, enrolled):
    tokens = sign_in(api_client, enrolled)
    assert not RefreshToken.objects.filter(token_hash=tokens["refresh"]).exists()
    assert RefreshToken.objects.count() == 1


def test_unknown_refresh_token_is_401(api_client):
    r = api_client.post("/api/v1/auth/refresh", {"refresh": "nope"}, format="json")
    assert r.status_code == 401 and r.json() == {"error": "refresh_invalid"}


def test_revoked_device_cannot_sign_in_or_use_old_access_token(api_client, enrol_device):
    old = enrol_device()
    old_tokens = sign_in(api_client, old)
    new = enrol_device()  # the same number moves to a new phone

    assert me(api_client, old_tokens["access"]).status_code == 401
    r = token_call(api_client, old, challenge(api_client, old.device_id))
    assert r.status_code == 401 and r.json() == {"error": "device_revoked"}
    refresh = api_client.post("/api/v1/auth/refresh", {"refresh": old_tokens["refresh"]}, format="json")
    assert refresh.status_code == 401
    assert me(api_client, sign_in(api_client, new)["access"]).status_code == 200


def test_inactive_user_is_refused(api_client, enrolled):
    tokens = sign_in(api_client, enrolled)
    User.objects.filter(pk=enrolled.device.user_id).update(is_active=False)
    assert me(api_client, tokens["access"]).status_code == 401


def test_me_without_token_or_with_garbage_is_401(api_client):
    assert api_client.get("/api/v1/me").status_code == 401
    assert me(api_client, "garbage").status_code == 401


def test_role_permissions(enrol_device):
    jobber = enrol_device().device.user
    householder = enrol_device(phone="0102030405", role="householder").device.user
    request = APIRequestFactory().get("/")

    request.user = jobber
    assert IsJobber().has_permission(request, None) is True
    assert IsHouseholder().has_permission(request, None) is False
    request.user = householder
    assert IsJobber().has_permission(request, None) is False
    assert IsHouseholder().has_permission(request, None) is True
    request.user = None
    assert IsJobber().has_permission(request, None) is False


def test_unknown_device_challenge_still_returns_nonce(api_client):
    key = DeviceKey()
    nonce = challenge(api_client, key.device_id)
    assert nonce
    r = token_call(api_client, key, nonce)
    assert r.status_code == 401 and r.json() == {"error": "unknown_device"}
