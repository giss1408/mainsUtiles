from datetime import timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import (
    AddressProof,
    HomeLocation,
    IdentityVerification,
    Status,
    VerificationPhoto,
)
from apps.verification.services import submissions
from apps.verification.services.submissions import VerificationError
from apps.verification.services.tiers import checklist, householder_tier

pytestmark = pytest.mark.django_db

NOW = timezone.now()


def stored_files(settings):
    directory = settings.VERIFICATION_STORAGE_DIR
    return sorted(directory.iterdir()) if directory.exists() else []


def send_identity(user, jpeg, seed=0, **overrides):
    values = {
        "document_type": "cni",
        "front": jpeg(seed),
        "back": jpeg(seed + 1),
        "selfie": jpeg(seed + 2),
        "captured_at": NOW,
    }
    values.update(overrides)
    return submissions.submit_identity(user, **values)


def send_address(user, jpeg, seed=10, **overrides):
    values = {
        "document_type": "facture_eau",
        "photo": jpeg(seed),
        "commune": "Cocody",
        "quartier": "Angré 8e tranche",
        "captured_at": NOW,
    }
    values.update(overrides)
    return submissions.submit_address_proof(user, **values)


def send_location(user, **overrides):
    values = {"lat": 5.3599, "lng": -3.9871, "accuracy_m": 12.4, "mock_location": False, "captured_at": NOW}
    values.update(overrides)
    return submissions.record_home_location(user, **values)


def error_code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


def test_identity_submission_stores_three_encrypted_photos(householder, jpeg, settings):
    record = send_identity(householder, jpeg, position=(5.36, -3.98))
    assert record.status == Status.SUBMITTED and record.document_type == "cni"
    assert record.full_name == "" and record.document_number == ""
    files = stored_files(settings)
    assert len(files) == 3
    for file in files:
        assert jpeg(0)[4:50] not in file.read_bytes()
    assert submissions.read_photo_bytes(record.front) == jpeg(0)
    assert submissions.read_photo_bytes(record.selfie) == jpeg(2)
    assert {record.front.kind, record.back.kind, record.selfie.kind} == {"id_front", "id_back", "selfie"}
    assert "5.36" not in record.front.capture_position and record.front.capture_position != ""


def test_second_identity_while_open_is_invalid_state(householder, jpeg):
    send_identity(householder, jpeg)
    assert error_code(lambda: send_identity(householder, jpeg, seed=20)) == "invalid_state"
    assert IdentityVerification.objects.count() == 1 and VerificationPhoto.objects.count() == 3


def test_refused_identity_can_be_sent_again_and_checklist_shows_the_new_one(householder, jpeg):
    first = send_identity(householder, jpeg)
    IdentityVerification.objects.filter(pk=first.pk).update(status=Status.REFUSED, reason="Photo floue")
    assert checklist(householder)["identity"] == {"status": "refused", "reason": "Photo floue"}

    send_identity(householder, jpeg, seed=20)
    assert checklist(householder)["identity"] == {"status": "submitted", "reason": ""}
    assert IdentityVerification.objects.filter(user=householder).count() == 2


def test_non_jpeg_and_oversized_photos_are_refused_and_leave_nothing(householder, jpeg, settings):
    assert error_code(lambda: send_identity(householder, jpeg, front=b"\x89PNG\r\n\x1a\n" + b"0" * 50)) == (
        "photo_invalid"
    )
    assert error_code(lambda: send_identity(householder, jpeg, front=b"")) == "photo_invalid"
    settings.VERIFICATION_PHOTO_MAX_BYTES = 100
    assert error_code(lambda: send_address(householder, jpeg)) == "photo_too_large"
    assert not IdentityVerification.objects.exists() and not AddressProof.objects.exists()
    assert not VerificationPhoto.objects.exists() and stored_files(settings) == []


def test_failure_on_third_photo_leaves_no_rows_and_no_files(householder, jpeg, settings):
    assert error_code(lambda: send_identity(householder, jpeg, selfie=b"not a photo")) == "photo_invalid"
    assert not VerificationPhoto.objects.exists() and stored_files(settings) == []
    assert checklist(householder)["identity"]["status"] == "not_started"
    send_identity(householder, jpeg)  # the step is still open to a correct submission


def test_staff_cannot_submit_and_jobbers_cannot_send_householder_steps(enrolled, staff_user, jpeg):
    assert error_code(lambda: send_identity(staff_user, jpeg)) == "forbidden"
    for user in (enrolled.device.user, staff_user):
        assert error_code(lambda user=user: send_address(user, jpeg)) == "forbidden"
        assert error_code(lambda user=user: send_location(user)) == "forbidden"


def test_unknown_commune_document_type_and_blank_quartier_are_refused(householder, jpeg, settings):
    assert error_code(lambda: send_address(householder, jpeg, commune="Paris")) == "commune_invalid"
    assert error_code(lambda: send_address(householder, jpeg, quartier="   ")) == "quartier_required"
    assert error_code(lambda: send_address(householder, jpeg, document_type="cni")) == "document_type_invalid"
    assert error_code(lambda: send_identity(householder, jpeg, document_type="facture_eau")) == (
        "document_type_invalid"
    )
    assert stored_files(settings) == []


def test_address_submission_keeps_commune_and_trimmed_quartier(householder, jpeg):
    record = send_address(householder, jpeg, quartier="  Angré  ")
    assert (record.commune, record.quartier) == ("Cocody", "Angré")
    assert checklist(householder)["address"] == {
        "status": "submitted",
        "reason": "",
        "commune": "Cocody",
        "quartier": "Angré",
        "expires_at": None,
    }


def test_same_image_on_two_accounts_is_flagged_photo_reused(householder, jpeg):
    other = User.objects.create_user(phone="+2250777777777", role="householder")
    first = send_identity(householder, jpeg)
    second = send_identity(other, jpeg, seed=0)
    assert first.flags == [] and second.flags == ["photo_reused"]
    assert send_address(other, jpeg, photo=jpeg(1)).flags == ["photo_reused"]


def test_inaccurate_location_is_refused_at_51_and_accepted_at_50(householder):
    assert error_code(lambda: send_location(householder, accuracy_m=50.6)) == "location_inaccurate"
    assert not HomeLocation.objects.exists()
    record = send_location(householder, accuracy_m=50.0)
    assert record.status == Status.SUBMITTED and record.accuracy_m == 50
    assert error_code(lambda: send_location(householder, lat=95.0)) == "location_inaccurate"


def test_location_is_stored_encrypted_and_mock_flag_recorded(householder):
    record = send_location(householder, mock_location=True)
    assert record.mock_location is True
    assert "5.3599" not in record.latitude and "3.9871" not in record.longitude
    assert submissions.location_coordinates(record) == (5.3599, -3.9871)


def test_new_location_replaces_the_previous_until_address_is_confirmed(householder, jpeg):
    first = send_location(householder)
    second = send_location(householder, lat=5.36)
    first.refresh_from_db()
    assert first.status == Status.REFUSED and second.status == Status.SUBMITTED
    assert checklist(householder)["home_location"] == {"status": "submitted", "reason": ""}

    proof = send_address(householder, jpeg)
    AddressProof.objects.filter(pk=proof.pk).update(status=Status.CONFIRMED)
    HomeLocation.objects.filter(pk=second.pk).update(status=Status.CONFIRMED)
    assert error_code(lambda: send_location(householder)) == "invalid_state"
    assert HomeLocation.objects.filter(user=householder).count() == 2


def test_checklist_for_a_new_householder_is_all_not_started_and_h0(householder, settings):
    result = checklist(householder)
    assert result["tier"] == "H0" and result["review_hours"] == 24
    assert result["communes"] == settings.SERVICE_COMMUNES
    assert result["identity"] == {"status": "not_started", "reason": ""}
    assert result["address"]["status"] == "not_started" and result["address"]["commune"] == ""
    assert result["home_location"] == {"status": "not_started", "reason": ""}


def test_tier_is_h1_only_when_all_three_are_confirmed_and_not_expired(householder, jpeg):
    identity = send_identity(householder, jpeg)
    proof = send_address(householder, jpeg)
    location = send_location(householder)
    IdentityVerification.objects.filter(pk=identity.pk).update(status=Status.CONFIRMED)
    HomeLocation.objects.filter(pk=location.pk).update(status=Status.CONFIRMED)
    assert householder_tier(householder) == "H0"

    AddressProof.objects.filter(pk=proof.pk).update(
        status=Status.CONFIRMED, expires_at=timezone.now() + timedelta(days=30)
    )
    assert householder_tier(householder) == "H1" and checklist(householder)["tier"] == "H1"

    # Past its date but not yet swept by the periodic task: already treated as expired.
    AddressProof.objects.filter(pk=proof.pk).update(expires_at=timezone.now() - timedelta(minutes=1))
    assert householder_tier(householder) == "H0"
    assert checklist(householder)["address"]["status"] == "expired"


def test_checklist_never_contains_names_numbers_or_coordinates(householder, jpeg):
    record = send_identity(householder, jpeg)
    send_address(householder, jpeg)
    send_location(householder)
    IdentityVerification.objects.filter(pk=record.pk).update(
        full_name="secret-name", document_number="secret-no"
    )
    text = str(checklist(householder))
    for secret in ("secret", "5.3599", "3.9871", ".bin", str(record.front.pk)):
        assert secret not in text
