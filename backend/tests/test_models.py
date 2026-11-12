import pytest
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction

from apps.accounts.models import User
from apps.audit.services import record


def test_same_phone_can_hold_both_roles_but_not_twice(db):
    User.objects.create(phone="+2250708091011", role="jobber")
    User.objects.create(phone="+2250708091011", role="householder")
    with pytest.raises(IntegrityError), transaction.atomic():
        User.objects.create(phone="+2250708091011", role="jobber")


def test_several_staff_users_need_no_phone(db):
    User.objects.create_user(username="a", password="pw", role="staff", is_staff=True)
    User.objects.create_user(username="b", password="pw", role="staff", is_staff=True)
    assert User.objects.filter(role="staff").count() == 2


def test_only_one_active_device_per_user(db, make_device):
    user = User.objects.create(phone="+2250708091011", role="jobber")
    make_device(user)
    with pytest.raises(IntegrityError), transaction.atomic():
        make_device(user)


def test_admin_action_is_append_only(db, staff_user):
    action = record(staff_user, "enrolment.approve", staff_user, reason="ok", note="x")
    assert action.target_type == "accounts.user"
    assert action.target_id == str(staff_user.pk)
    assert action.metadata == {"note": "x"}
    with pytest.raises(ValueError):
        action.save()
    with pytest.raises(ValueError):
        action.delete()


def test_enrolment_agent_group_exists(db):
    perms = set(Group.objects.get(name="enrolment_agent").permissions.values_list("codename", flat=True))
    assert {"review_enrolment", "send_enrolment_code", "view_deviceenrolmentrequest"} <= perms
