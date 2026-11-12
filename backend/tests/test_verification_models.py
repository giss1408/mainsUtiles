import uuid
from datetime import date

import pytest
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import (
    AddressProof,
    HomeLocation,
    IdentityVerification,
    Status,
    VerificationPhoto,
)

pytestmark = pytest.mark.django_db


@pytest.fixture
def user():
    return User.objects.create_user(phone="+2250708091011", role="householder")


@pytest.fixture
def other():
    return User.objects.create_user(phone="+2250102030405", role="householder")


def photo(owner, kind="id_front"):
    return VerificationPhoto.objects.create(
        owner=owner,
        kind=kind,
        storage_name=f"{uuid.uuid4()}.bin",
        sha256="0" * 64,
        captured_at=timezone.now(),
    )


def identity(owner, status=Status.SUBMITTED, **extra):
    return IdentityVerification.objects.create(
        user=owner,
        status=status,
        front=photo(owner, "id_front"),
        back=photo(owner, "id_back"),
        selfie=photo(owner, "selfie"),
        document_type="cni",
        **extra,
    )


def address(owner, status=Status.SUBMITTED, **extra):
    return AddressProof.objects.create(
        user=owner,
        status=status,
        photo=photo(owner, "address_proof"),
        document_type="facture_eau",
        commune="Cocody",
        quartier="Angré",
        **extra,
    )


def location(owner, status=Status.SUBMITTED):
    return HomeLocation.objects.create(
        user=owner, status=status, latitude="x", longitude="y", accuracy_m=12, captured_at=timezone.now()
    )


@pytest.mark.parametrize("make", [identity, address, location])
def test_one_open_record_per_user(user, make):
    make(user, status=Status.REFUSED)
    make(user, status=Status.EXPIRED)
    make(user)
    for open_status in (Status.SUBMITTED, Status.IN_REVIEW, Status.CONFIRMED):
        with pytest.raises(IntegrityError), transaction.atomic():
            make(user, status=open_status)


def test_confirmed_document_hash_is_unique(user, other):
    identity(user, status=Status.CONFIRMED, document_number_hash="h1")
    identity(other, document_number_hash="")  # not yet recorded: blank hashes never collide
    with pytest.raises(IntegrityError), transaction.atomic():
        IdentityVerification.objects.filter(user=other).update(
            status=Status.CONFIRMED, document_number_hash="h1"
        )


def test_confirmed_reference_hash_is_unique(user, other):
    address(user, status=Status.CONFIRMED, reference_hash="r1", issued_on=date(2026, 10, 1))
    address(other)
    with pytest.raises(IntegrityError), transaction.atomic():
        AddressProof.objects.filter(user=other).update(status=Status.CONFIRMED, reference_hash="r1")


def test_two_unconfirmed_records_may_share_blank_hashes(user, other):
    identity(user)
    identity(other)
    address(user)
    address(other)


def test_verification_agent_group_has_review_and_photo_permissions():
    codenames = set(
        Group.objects.get(name="verification_agent").permissions.values_list("codename", flat=True)
    )
    assert {
        "review_verification",
        "view_verification_photo",
        "view_identityverification",
        "view_addressproof",
        "view_homelocation",
    } <= codenames


def test_enrolment_agents_do_not_get_verification_rights():
    codenames = set(Group.objects.get(name="enrolment_agent").permissions.values_list("codename", flat=True))
    assert "review_verification" not in codenames and "view_verification_photo" not in codenames
