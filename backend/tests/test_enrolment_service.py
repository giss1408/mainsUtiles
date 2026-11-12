import uuid
from datetime import timedelta

import pytest
from django.utils import timezone
from freezegun import freeze_time

from apps.accounts.models import Device, DeviceEnrolmentRequest, User
from apps.accounts.services.enrolment import (
    EnrolmentError,
    apply,
    approve,
    confirm,
    hold,
    issue_code,
    refuse,
)
from apps.accounts.tasks import expire_stale_enrolments
from apps.audit.models import AdminAction

KEY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


@pytest.fixture
def application(db):
    def _apply(**overrides):
        values = {
            "phone": "0708091011",
            "role": "jobber",
            "device_id": uuid.uuid4(),
            "device_model": "Tecno Spark",
            "platform": "android",
            "public_key": KEY,
            "client_token": "tok",
        }
        values.update(overrides)
        return apply(**values)

    return _apply


@pytest.fixture
def other_staff(db):
    return User.objects.create_user(username="nogroup", password="pw", role="staff", is_staff=True)


def enrol(application, staff, **overrides):
    """Run the whole flow and return (request, device, code)."""
    req = application(**overrides)
    if req.kind == "new_device":
        DeviceEnrolmentRequest.objects.filter(pk=req.pk).update(selfie_verified_at=timezone.now())
        req.refresh_from_db()
    approve(req, staff=staff)
    code = issue_code(req, staff=staff)
    device = confirm(req, client_token=overrides.get("client_token", "tok"), code=code)
    return req, device, code


def wrong(code):
    return "000000" if code != "000000" else "111111"


def test_apply_normalises_phone_and_starts_pending(application):
    req = application(approx_lat=5.35912, approx_lng=-4.00834)
    assert (req.phone, req.status, req.kind, req.integrity_verdict) == (
        "+2250708091011",
        "pending",
        "new_account",
        "unchecked",
    )
    req.refresh_from_db()
    assert (str(req.approx_lat), str(req.approx_lng)) == ("5.36", "-4.01")
    assert "tok" not in req.client_token_hash


def test_apply_with_invalid_phone_is_rejected(application):
    with pytest.raises(EnrolmentError) as e:
        application(phone="12345")
    assert e.value.code == "invalid_phone"


def test_apply_twice_with_same_device_and_token_returns_same_row(application):
    did = uuid.uuid4()
    assert application(device_id=did).id == application(device_id=did).id
    assert DeviceEnrolmentRequest.objects.count() == 1


def test_fourth_application_for_a_phone_in_a_day_is_rate_limited(application):
    for _ in range(3):
        application()
    with pytest.raises(EnrolmentError) as e:
        application()
    assert e.value.code == "rate_limited"


def test_ip_limit_applies_across_phones(application, settings):
    settings.ENROLMENT_MAX_PER_IP_PER_DAY = 2
    application(phone="0708091011", ip="10.1.1.1")
    application(phone="0102030405", ip="10.1.1.1")
    with pytest.raises(EnrolmentError) as e:
        application(phone="0505050505", ip="10.1.1.1")
    assert e.value.code == "rate_limited"


def test_device_applying_for_second_number_is_flagged(application):
    did = uuid.uuid4()
    first = application(device_id=did, client_token="a")
    second = application(device_id=did, client_token="b", phone="0102030405")
    assert first.flags == []
    assert "device_multiple_numbers" in second.flags


def test_full_happy_path_creates_user_and_active_device(application, staff_user):
    req = application()
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    assert len(code) == 6 and code.isdigit()
    device = confirm(req, client_token="tok", code=code)
    req.refresh_from_db()
    assert req.status == "completed"
    assert device.status == "active" and device.user.role == "jobber"
    assert device.id == req.device_id and device.public_key == KEY
    assert (req.approved_by, req.sent_by) == (staff_user, staff_user)
    actions = AdminAction.objects.filter(action__in=["enrolment.approve", "enrolment.send_code"])
    assert actions.count() == 2
    assert code not in str(list(AdminAction.objects.values()))
    assert code not in str(DeviceEnrolmentRequest.objects.filter(pk=req.pk).values()[0])


def test_confirm_again_after_success_returns_same_device(application, staff_user):
    req, device, code = enrol(application, staff_user)
    again = confirm(req, client_token="tok", code=code)
    assert again.pk == device.pk
    assert Device.objects.count() == 1


def test_older_number_after_resend_is_code_replaced_and_new_one_works(application, staff_user):
    req = application()
    approve(req, staff=staff_user)
    first = issue_code(req, staff=staff_user)
    second = issue_code(req, staff=staff_user)
    while second == first:
        second = issue_code(req, staff=staff_user)
    with pytest.raises(EnrolmentError) as e:
        confirm(req, client_token="tok", code=first)
    assert e.value.code == "code_replaced"
    req.refresh_from_db()
    assert req.code_attempts == 0
    assert confirm(req, client_token="tok", code=second).status == "active"


def test_second_approval_is_invalid_state_with_single_audit_row(application, staff_user):
    req = application()
    stale_copy = DeviceEnrolmentRequest.objects.get(pk=req.pk)
    approve(req, staff=staff_user)
    with pytest.raises(EnrolmentError) as e:
        approve(stale_copy, staff=staff_user)
    assert e.value.code == "invalid_state"
    assert AdminAction.objects.filter(action="enrolment.approve").count() == 1


def test_five_wrong_numbers_lock_the_application(application, staff_user):
    req = application()
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    for _ in range(4):
        with pytest.raises(EnrolmentError) as e:
            confirm(req, client_token="tok", code=wrong(code))
        assert e.value.code == "code_invalid"
    with pytest.raises(EnrolmentError) as e:
        confirm(req, client_token="tok", code=wrong(code))
    assert e.value.code == "locked"
    with pytest.raises(EnrolmentError) as e:
        confirm(req, client_token="tok", code=code)
    assert e.value.code == "locked"
    req.refresh_from_db()
    assert req.status == "locked" and Device.objects.count() == 0


def test_expired_number_raises_code_expired(application, staff_user):
    with freeze_time("2026-11-12 10:00:00") as clock:
        req = application()
        approve(req, staff=staff_user)
        code = issue_code(req, staff=staff_user)
        clock.tick(timedelta(minutes=61))
        with pytest.raises(EnrolmentError) as e:
            confirm(req, client_token="tok", code=code)
        assert e.value.code == "code_expired"
        fresh = issue_code(req, staff=staff_user)
        assert confirm(req, client_token="tok", code=fresh).status == "active"


def test_wrong_client_token_is_forbidden(application, staff_user):
    req = application()
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    with pytest.raises(EnrolmentError) as e:
        confirm(req, client_token="someone-else", code=code)
    assert e.value.code == "forbidden"


def test_new_device_cannot_be_approved_without_selfie(application, staff_user):
    enrol(application, staff_user)
    req = application()
    assert req.kind == "new_device"
    with pytest.raises(EnrolmentError) as e:
        approve(req, staff=staff_user)
    assert e.value.code == "selfie_required"
    req.refresh_from_db()
    assert req.status == "pending"


def test_new_device_confirmation_revokes_previous_device(application, staff_user):
    _, old_device, _ = enrol(application, staff_user)
    req = application()
    DeviceEnrolmentRequest.objects.filter(pk=req.pk).update(selfie_verified_at=timezone.now())
    approve(req, staff=staff_user)
    code = issue_code(req, staff=staff_user)
    old_device.refresh_from_db()
    assert old_device.status == "active"  # still usable until the new phone is confirmed
    new_device = confirm(req, client_token="tok", code=code)
    old_device.refresh_from_db()
    assert old_device.status == "revoked" and old_device.revoked_at is not None
    assert new_device.status == "active" and new_device.user == old_device.user
    assert User.objects.filter(role="jobber").count() == 1


def test_revoked_device_id_re_enrolling_is_reactivated_with_new_key(application, staff_user):
    first_id = uuid.uuid4()
    enrol(application, staff_user, device_id=first_id)
    enrol(application, staff_user)  # a second phone takes over
    new_key = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    _, device, _ = enrol(application, staff_user, device_id=first_id, public_key=new_key)
    assert device.id == first_id and device.status == "active" and device.public_key == new_key
    assert device.revoked_at is None
    assert Device.objects.filter(status="active").count() == 1


def test_staff_without_permission_cannot_approve_or_send(application, staff_user, other_staff):
    req = application()
    with pytest.raises(EnrolmentError) as e:
        approve(req, staff=other_staff)
    assert e.value.code == "forbidden"
    approve(req, staff=staff_user)
    with pytest.raises(EnrolmentError) as e:
        issue_code(req, staff=other_staff)
    assert e.value.code == "forbidden"
    req.refresh_from_db()
    assert req.status == "approved"


def test_refuse_and_hold_record_reason_and_audit(application, staff_user):
    held = application()
    hold(held, staff=staff_user, reason="Numéro à vérifier")
    held.refresh_from_db()
    assert (held.status, held.reason) == ("held", "Numéro à vérifier")
    refuse(held, staff=staff_user, reason="Numéro injoignable")
    held.refresh_from_db()
    assert (held.status, held.reason) == ("refused", "Numéro injoignable")
    reasons = list(
        AdminAction.objects.filter(target_id=str(held.pk))
        .order_by("created_at")
        .values_list("action", "reason")
    )
    assert reasons == [("enrolment.hold", "Numéro à vérifier"), ("enrolment.refuse", "Numéro injoignable")]
    with pytest.raises(EnrolmentError) as e:
        approve(held, staff=staff_user)
    assert e.value.code == "invalid_state"


def test_stale_applications_expire(application, staff_user):
    with freeze_time("2026-11-01 10:00:00") as clock:
        old = application()
        done, _, _ = enrol(application, staff_user, phone="0102030405")
        clock.tick(timedelta(days=8))
        recent = application(phone="0505050505")
        assert expire_stale_enrolments() == 1
    for req in (old, done, recent):
        req.refresh_from_db()
    assert (old.status, done.status, recent.status) == ("expired", "completed", "pending")
