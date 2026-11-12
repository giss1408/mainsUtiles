import re
from datetime import timedelta

import pytest
from django.contrib.auth.models import Permission
from django.core.exceptions import PermissionDenied
from django.test import Client
from freezegun import freeze_time

from apps.accounts.models import Device, User
from apps.accounts.services import enrolment, staff_auth
from apps.audit.models import AdminAction
from tests.helpers import DeviceKey

pytestmark = pytest.mark.django_db

QUEUE = "/api/v1/staff/enrolments"


class StaffKey(DeviceKey):
    """A staff phone: a device identity plus the username typed on it."""

    username = "agent"

    def registration(self, password, username=None):
        return {
            "username": username or self.username,
            "password": password,
            "device_id": self.device_id,
            "device_model": "Samsung A15",
            "platform": "android",
            "public_key": self.public_key,
        }


def staff_login(api_client, key, password, username=None):
    nonce = api_client.post("/api/v1/auth/challenge", {"device_id": key.device_id}, format="json").json()[
        "nonce"
    ]
    body = {
        "username": username or key.username,
        "password": password,
        "device_id": key.device_id,
        "nonce": nonce,
        "signature": key.sign(f"petitgombo-auth:{key.device_id}:{nonce}"),
    }
    return api_client.post("/api/v1/staff/auth/login", body, format="json")


def register(api_client, key, password="pw"):
    response = api_client.post("/api/v1/staff/devices", key.registration(password=password), format="json")
    assert response.status_code == 201, response.content
    return Device.objects.get(pk=key.device_id)


@pytest.fixture
def staff_key():
    return StaffKey()


@pytest.fixture
def superuser(db):
    return User.objects.create_superuser(username="root", password="rootpw")


@pytest.fixture
def active_staff(api_client, staff_user, staff_key, superuser):
    """A staff member whose phone is registered, activated and signed in."""
    device = register(api_client, staff_key)
    staff_auth.activate_device(device, admin=superuser)
    response = staff_login(api_client, staff_key, "pw")
    assert response.status_code == 200, response.content
    staff_key.tokens = response.json()
    staff_key.bearer = f"Bearer {staff_key.tokens['access']}"
    staff_key.user = staff_user
    return staff_key


def post(api_client, path, bearer, body=None):
    return api_client.post(path, body or {}, format="json", HTTP_AUTHORIZATION=bearer)


def test_register_staff_device_is_pending_and_login_refused_until_activated(
    api_client, staff_user, staff_key
):
    r = api_client.post("/api/v1/staff/devices", staff_key.registration(password="pw"), format="json")
    assert r.status_code == 201 and r.json() == {"status": "pending"}
    login = staff_login(api_client, staff_key, "pw")
    assert login.status_code == 401 and login.json() == {"error": "device_pending"}


def test_registering_the_same_device_again_changes_nothing(api_client, staff_user, staff_key, superuser):
    device = register(api_client, staff_key)
    staff_auth.activate_device(device, admin=superuser)
    other = StaffKey()
    body = staff_key.registration(password="pw") | {"public_key": other.public_key}
    r = api_client.post("/api/v1/staff/devices", body, format="json")
    assert r.status_code == 200 and r.json() == {"status": "active"}
    device.refresh_from_db()
    assert device.public_key == staff_key.public_key
    assert Device.objects.count() == 1


def test_app_user_cannot_register_a_staff_device(api_client, staff_key):
    User.objects.create_user(username="notstaff", password="pw", role="jobber", phone="+2250101010101")
    r = api_client.post(
        "/api/v1/staff/devices", staff_key.registration(password="pw", username="notstaff"), format="json"
    )
    assert r.status_code == 401 and r.json() == {"error": "bad_credentials"}
    assert not Device.objects.exists()


def test_activated_device_logs_in_and_lists_pending_queue(api_client, active_staff, pending_request):
    r = api_client.get(QUEUE, HTTP_AUTHORIZATION=active_staff.bearer)
    assert r.status_code == 200
    assert [i["id"] for i in r.json()["results"]] == [str(pending_request.id)]
    item = r.json()["results"][0]
    assert set(item) == {
        "id",
        "phone",
        "role",
        "kind",
        "status",
        "flags",
        "device_model",
        "platform",
        "integrity_verdict",
        "created_at",
    }
    assert item["phone"] == "+2250708091011" and item["status"] == "pending"


def test_me_lists_permission_codenames(api_client, active_staff):
    body = api_client.get("/api/v1/staff/me", HTTP_AUTHORIZATION=active_staff.bearer).json()
    assert body["id"] == str(active_staff.user.pk) and body["username"] == "agent"
    assert {"review_enrolment", "send_enrolment_code"} <= set(body["permissions"])


def test_approve_then_send_returns_whatsapp_url_with_working_code(api_client, active_staff, pending_request):
    r = post(api_client, f"{QUEUE}/{pending_request.id}/approve", active_staff.bearer)
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert r.json()["approved_at"] is not None

    r = post(api_client, f"{QUEUE}/{pending_request.id}/send", active_staff.bearer)
    assert r.status_code == 200 and set(r.json()) == {"whatsapp_url"}
    assert "no-store" in r["Cache-Control"]
    url = r.json()["whatsapp_url"]
    assert url.startswith("https://wa.me/2250708091011?text=")
    code = re.search(r"confirmation%20est%20(\d{6})", url).group(1)
    assert enrolment.confirm(pending_request, client_token="tok", code=code).status == "active"


def test_hold_moves_the_application_to_the_held_list_with_its_reason(
    api_client, active_staff, pending_request
):
    r = post(api_client, f"{QUEUE}/{pending_request.id}/hold", active_staff.bearer, {"reason": "À rappeler"})
    assert r.status_code == 200 and r.json()["status"] == "held"
    assert api_client.get(QUEUE, HTTP_AUTHORIZATION=active_staff.bearer).json()["results"] == []
    held = api_client.get(f"{QUEUE}?status=held", HTTP_AUTHORIZATION=active_staff.bearer).json()
    assert [i["id"] for i in held["results"]] == [str(pending_request.id)]

    detail = api_client.get(f"{QUEUE}/{pending_request.id}", HTTP_AUTHORIZATION=active_staff.bearer).json()
    assert detail["reason"] == "À rappeler"
    assert detail["approved_at"] is None and detail["sent_at"] is None
    assert not any("hash" in field for field in detail)


def test_unknown_status_filter_is_400(api_client, active_staff):
    r = api_client.get(f"{QUEUE}?status=completed", HTTP_AUTHORIZATION=active_staff.bearer)
    assert r.status_code == 400


def test_wrong_password_and_unknown_user_give_same_error(api_client, active_staff):
    wrong_password = staff_login(api_client, active_staff, "nope")
    unknown_user = staff_login(api_client, active_staff, "pw", username="ghost")
    assert wrong_password.status_code == unknown_user.status_code == 401
    assert wrong_password.json() == unknown_user.json() == {"error": "bad_credentials"}

    r = api_client.post("/api/v1/staff/devices", StaffKey().registration(password="nope"), format="json")
    assert r.status_code == 401 and r.json() == {"error": "bad_credentials"}


def test_sixth_failed_login_is_423_locked_even_with_right_password(api_client, active_staff):
    with freeze_time("2026-11-12 10:00:00") as clock:
        for _ in range(5):
            assert staff_login(api_client, active_staff, "nope").json() == {"error": "bad_credentials"}
        locked = staff_login(api_client, active_staff, "pw")
        assert locked.status_code == 423 and locked.json() == {"error": "locked"}
        # The lock also closes the device registration door.
        r = api_client.post("/api/v1/staff/devices", StaffKey().registration(password="pw"), format="json")
        assert r.status_code == 423
        clock.tick(timedelta(minutes=16))
        assert staff_login(api_client, active_staff, "pw").status_code == 200


def test_successful_login_clears_the_failure_count(api_client, active_staff):
    for _ in range(4):
        staff_login(api_client, active_staff, "nope")
    assert staff_login(api_client, active_staff, "pw").status_code == 200
    for _ in range(4):
        staff_login(api_client, active_staff, "nope")
    assert staff_login(api_client, active_staff, "pw").status_code == 200


def test_login_with_another_key_is_rejected(api_client, active_staff):
    thief = StaffKey()
    thief.device_id = active_staff.device_id
    r = staff_login(api_client, thief, "pw")
    assert r.status_code == 401 and r.json() == {"error": "signature_invalid"}


def test_staff_without_permission_gets_403_on_queue_and_send(api_client, active_staff, pending_request):
    active_staff.user.groups.clear()
    base = f"{QUEUE}/{pending_request.id}"
    assert api_client.get(QUEUE, HTTP_AUTHORIZATION=active_staff.bearer).status_code == 403
    assert post(api_client, f"{base}/approve", active_staff.bearer).status_code == 403
    assert post(api_client, f"{base}/send", active_staff.bearer).status_code == 403

    # Review rights alone do not allow sending the confirmation number.
    active_staff.user.user_permissions.add(Permission.objects.get(codename="review_enrolment"))
    assert post(api_client, f"{base}/approve", active_staff.bearer).status_code == 200
    assert post(api_client, f"{base}/send", active_staff.bearer).status_code == 403
    pending_request.refresh_from_db()
    assert pending_request.status == "approved" and pending_request.code_hash == ""


def test_jobber_token_gets_403_on_all_staff_endpoints(api_client, enrolled, pending_request):
    nonce = api_client.post(
        "/api/v1/auth/challenge", {"device_id": enrolled.device_id}, format="json"
    ).json()["nonce"]
    body = {
        "device_id": enrolled.device_id,
        "nonce": nonce,
        "signature": enrolled.sign(f"petitgombo-auth:{enrolled.device_id}:{nonce}"),
    }
    bearer = f"Bearer {api_client.post('/api/v1/auth/token', body, format='json').json()['access']}"
    base = f"{QUEUE}/{pending_request.id}"

    for path in ("/api/v1/staff/me", QUEUE, base):
        assert api_client.get(path, HTTP_AUTHORIZATION=bearer).status_code == 403, path
    for action in ("approve", "refuse", "hold", "send"):
        r = post(api_client, f"{base}/{action}", bearer, {"reason": "x"})
        assert r.status_code == 403, action
    pending_request.refresh_from_db()
    assert pending_request.status == "pending"


def test_staff_endpoints_without_token_are_401(api_client, pending_request):
    assert api_client.get(QUEUE).status_code == 401
    assert api_client.get("/api/v1/staff/me").status_code == 401
    assert api_client.post(f"{QUEUE}/{pending_request.id}/approve").status_code == 401


def test_activation_is_superuser_only_and_revokes_previous_staff_device(
    api_client, staff_user, staff_key, superuser
):
    first = register(api_client, staff_key)
    with pytest.raises(PermissionDenied):
        staff_auth.activate_device(first, admin=staff_user)
    first.refresh_from_db()
    assert first.status == "pending"

    staff_auth.activate_device(first, admin=superuser)
    second_key = StaffKey()
    second = register(api_client, second_key)
    staff_auth.activate_device(second, admin=superuser)

    first.refresh_from_db()
    second.refresh_from_db()
    assert first.status == "revoked" and first.revoked_at is not None
    assert second.status == "active"
    assert staff_login(api_client, staff_key, "pw").json() == {"error": "device_revoked"}
    assert staff_login(api_client, second_key, "pw").status_code == 200
    actions = AdminAction.objects.filter(action="staff_device.activate")
    assert actions.count() == 2 and all(a.actor_id == superuser.pk for a in actions)


def test_revoked_device_cannot_be_activated_again(api_client, staff_user, staff_key, superuser):
    device = register(api_client, staff_key)
    staff_auth.revoke_device(device, admin=superuser)
    with pytest.raises(staff_auth.AuthError) as error:
        staff_auth.activate_device(device, admin=superuser)
    assert error.value.code == "invalid_state"


def test_revoked_staff_device_token_is_401(api_client, active_staff, superuser):
    device = Device.objects.get(pk=active_staff.device_id)
    with pytest.raises(PermissionDenied):
        staff_auth.revoke_device(device, admin=active_staff.user)
    staff_auth.revoke_device(device, admin=superuser)

    assert api_client.get(QUEUE, HTTP_AUTHORIZATION=active_staff.bearer).status_code == 401
    r = api_client.post("/api/v1/auth/refresh", {"refresh": active_staff.tokens["refresh"]}, format="json")
    assert r.status_code == 401
    assert AdminAction.objects.filter(action="staff_device.revoke").count() == 1


def test_staff_access_token_expires_after_ten_minutes(api_client, staff_user, staff_key, superuser):
    staff_auth.activate_device(register(api_client, staff_key), admin=superuser)
    with freeze_time("2026-11-12 10:00:00") as clock:
        bearer = f"Bearer {staff_login(api_client, staff_key, 'pw').json()['access']}"
        clock.tick(timedelta(minutes=9))
        assert api_client.get(QUEUE, HTTP_AUTHORIZATION=bearer).status_code == 200
        clock.tick(timedelta(minutes=2))
        assert api_client.get(QUEUE, HTTP_AUTHORIZATION=bearer).status_code == 401


def test_refuse_without_reason_is_400(api_client, active_staff, pending_request):
    base = f"{QUEUE}/{pending_request.id}"
    assert post(api_client, f"{base}/refuse", active_staff.bearer).status_code == 400
    assert post(api_client, f"{base}/refuse", active_staff.bearer, {"reason": "   "}).status_code == 400
    assert post(api_client, f"{base}/hold", active_staff.bearer).status_code == 400
    pending_request.refresh_from_db()
    assert pending_request.status == "pending"

    r = post(api_client, f"{base}/refuse", active_staff.bearer, {"reason": "Numéro injoignable"})
    assert r.status_code == 200 and r.json()["status"] == "refused"
    assert r.json()["reason"] == "Numéro injoignable"


def test_second_approve_is_409_invalid_state(api_client, active_staff, pending_request):
    path = f"{QUEUE}/{pending_request.id}/approve"
    assert post(api_client, path, active_staff.bearer).status_code == 200
    again = post(api_client, path, active_staff.bearer)
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"
    assert AdminAction.objects.filter(action="enrolment.approve").count() == 1


def test_unknown_application_is_404(api_client, active_staff):
    missing = "00000000-0000-4000-8000-000000000000"
    assert api_client.get(f"{QUEUE}/{missing}", HTTP_AUTHORIZATION=active_staff.bearer).status_code == 404
    assert post(api_client, f"{QUEUE}/{missing}/approve", active_staff.bearer).status_code == 404


def test_staff_device_console_is_for_superusers_only(
    api_client, staff_user, staff_key, superuser, agent_client
):
    device = register(api_client, staff_key)
    page = "/admin/accounts/staffdevice/"
    assert agent_client.get(page).status_code == 403

    root = Client()
    root.force_login(superuser)
    html = root.get(page).content.decode()
    assert "Appareils du personnel" in html and "Samsung A15" in html
    assert "Activer" in html and "Révoquer" in html

    r = root.post(page, {"action": "activate", "_selected_action": [str(device.pk)]})
    assert r.status_code == 302
    device.refresh_from_db()
    assert device.status == "active"
    r = root.post(page, {"action": "revoke", "_selected_action": [str(device.pk)]})
    device.refresh_from_db()
    assert device.status == "revoked"

    # The agent cannot run the action by posting to the page either.
    other = register(api_client, StaffKey())
    agent_client.post(page, {"action": "activate", "_selected_action": [str(other.pk)]})
    other.refresh_from_db()
    assert other.status == "pending"
