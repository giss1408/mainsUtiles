import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import Guarantor, IdentityVerification, Status, VerificationPhoto
from apps.verification.services import submissions
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError

pytestmark = pytest.mark.django_db

NOW = timezone.now()
PHONE = "+2250505050505"


@pytest.fixture
def jobber():
    return User.objects.create_user(phone=PHONE, role="jobber")


def send(user, jpeg, seed=20, **overrides):
    values = {
        "document_type": "facture_eau",
        "photo": jpeg(seed),
        "guarantor_name": "Kouassi Yao",
        "guarantor_phone": "07 07 07 07 07",
        "relationship": "parent",
        "captured_at": NOW,
    }
    values.update(overrides)
    return submissions.submit_guarantor(user, **values)


def code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


def test_jobber_can_submit_identity(jobber, jpeg):
    record = submissions.submit_identity(
        jobber, document_type="cni", front=jpeg(0), back=jpeg(1), selfie=jpeg(2), captured_at=NOW
    )
    assert record.status == Status.SUBMITTED
    assert IdentityVerification.objects.filter(user=jobber).count() == 1


def test_householder_cannot_submit_a_guarantor(householder, jpeg):
    assert code(lambda: send(householder, jpeg)) == "forbidden"


def test_guarantor_is_stored_encrypted(jobber, jpeg):
    record = send(jobber, jpeg)
    stored = Guarantor.objects.get(pk=record.pk)
    name, phone = stored.guarantor_name, stored.guarantor_phone
    assert "Kouassi" not in name and "0707070707" not in phone and "+225" not in phone
    assert decrypt_text(name) == "Kouassi Yao" and decrypt_text(phone) == "+2250707070707"
    assert record.relationship == "parent" and record.status == Status.SUBMITTED


@pytest.mark.parametrize("typed", ["+2250505050505", "0505050505", "00225 05 05 05 05 05"])
def test_guarantor_phone_same_as_the_jobbers_is_refused_in_any_format(jobber, jpeg, typed):
    assert code(lambda: send(jobber, jpeg, guarantor_phone=typed)) == "guarantor_phone_own"


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        ({"guarantor_phone": "12345"}, "guarantor_phone_invalid"),
        ({"guarantor_name": "   "}, "guarantor_name_required"),
        ({"relationship": "friend"}, "relationship_invalid"),
        ({"document_type": "cni"}, "document_type_invalid"),
    ],
)
def test_invalid_fields_are_refused(jobber, jpeg, overrides, expected):
    assert code(lambda: send(jobber, jpeg, **overrides)) == expected


def test_second_open_guarantor_is_refused(jobber, jpeg):
    send(jobber, jpeg)
    assert code(lambda: send(jobber, jpeg, seed=30)) == "invalid_state"


def test_refused_guarantor_can_be_resubmitted(jobber, jpeg):
    first = send(jobber, jpeg)
    Guarantor.objects.filter(pk=first.pk).update(status=Status.REFUSED)
    assert send(jobber, jpeg, seed=30).status == Status.SUBMITTED


def test_failed_submission_leaves_no_file(jobber, jpeg, settings):
    assert code(lambda: send(jobber, jpeg, photo=b"not a photo")) == "photo_invalid"
    assert not VerificationPhoto.objects.exists()
    directory = settings.VERIFICATION_STORAGE_DIR
    assert not directory.exists() or list(directory.iterdir()) == []


def test_a_photo_already_sent_by_another_account_is_flagged(jobber, jpeg):
    other = User.objects.create_user(phone="+2250101010101", role="jobber")
    send(other, jpeg, guarantor_phone="07 07 07 07 08")
    record = send(jobber, jpeg)
    assert "photo_reused" in record.flags
