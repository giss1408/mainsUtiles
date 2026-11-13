import pytest
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import Guarantor, Status, VerificationPhoto


def _guarantor(user, status=Status.SUBMITTED, seed="a"):
    photo = VerificationPhoto.objects.create(
        owner=user,
        kind=VerificationPhoto.Kind.GUARANTOR_BILL,
        storage_name=f"{seed}-{user.pk}.bin",
        sha256=seed * 64,
        captured_at=timezone.now(),
    )
    return Guarantor.objects.create(
        user=user,
        photo=photo,
        document_type="facture_eau",
        guarantor_name="enc",
        guarantor_phone="enc",
        guarantor_phone_hash="h" * 64,
        relationship="parent",
        status=status,
    )


@pytest.fixture
def jobber(db):
    return User.objects.create_user(phone="+2250707070707", role="jobber")


@pytest.mark.django_db(transaction=True)
def test_one_open_guarantor_per_user(jobber):
    _guarantor(jobber)
    with pytest.raises(IntegrityError), transaction.atomic():
        _guarantor(jobber, seed="b")


def test_a_refused_guarantor_does_not_block_a_new_one(jobber):
    _guarantor(jobber, status=Status.REFUSED)
    _guarantor(jobber, seed="b")
    assert Guarantor.objects.filter(user=jobber).count() == 2


def test_photo_kind_guarantor_bill_exists():
    assert VerificationPhoto.Kind.GUARANTOR_BILL == "guarantor_bill"


def test_verification_agent_group_can_view_guarantors(db):
    group = Group.objects.get(name="verification_agent")
    assert group.permissions.filter(codename="view_guarantor").exists()
