from datetime import date, timedelta

import pytest
from django.utils import timezone
from freezegun import freeze_time

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.verification.models import AddressProof, HomeLocation, IdentityVerification, Status
from apps.verification.services import review
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError
from apps.verification.services.tiers import checklist, householder_tier
from apps.verification.tasks import expire_address_proofs
from tests.test_verification_submissions import send_address, send_identity, send_location

pytestmark = pytest.mark.django_db

TODAY = date(2026, 11, 12)


@pytest.fixture(autouse=True)
def _fixed_day():
    with freeze_time("2026-11-12 10:00:00"):
        yield


def code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


def identity_values(**overrides):
    values = {
        "full_name": "Kouassi Aya",
        "date_of_birth": date(1990, 5, 17),
        "document_number": "CI 001-234 567",
        "document_expires_on": date(2030, 1, 1),
    }
    values.update(overrides)
    return values


def address_values(**overrides):
    values = {
        "holder_name": "Kouassi Aya",
        "reference_number": "CIE-889900",
        "issued_on": date(2026, 10, 1),
        "name_matches": True,
        "address_consistent": True,
    }
    values.update(overrides)
    return values


def other_householder(phone="+2250777777777"):
    return User.objects.create_user(phone=phone, role="householder")


def confirmed_identity(user, jpeg, verifier, seed=0, **overrides):
    record = send_identity(user, jpeg, seed=seed)
    review.confirm_identity(record, staff=verifier, **identity_values(**overrides))
    return record


def test_confirm_identity_stores_encrypted_fields_and_audits(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    review.confirm_identity(record, staff=verifier, **identity_values())

    record.refresh_from_db()
    assert record.status == Status.CONFIRMED and record.reviewed_by == verifier
    assert record.reviewed_at is not None and record.document_expires_on == date(2030, 1, 1)
    for column in (record.full_name, record.date_of_birth, record.document_number):
        assert "Kouassi" not in column and "1990" not in column and "001234567" not in column
    assert decrypt_text(record.full_name) == "Kouassi Aya"
    assert decrypt_text(record.date_of_birth) == "1990-05-17"
    assert decrypt_text(record.document_number) == "CI 001-234 567"
    assert len(record.document_number_hash) == 64
    action = AdminAction.objects.get(action="verification.identity.confirm")
    assert action.actor == verifier and action.target_id == str(record.pk)
    assert "Kouassi" not in str(action.metadata) and "001" not in str(action.metadata)


def test_turns_18_tomorrow_is_refused_and_turned_18_today_is_accepted(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    tomorrow = identity_values(date_of_birth=date(2008, 11, 13))
    assert code(lambda: review.confirm_identity(record, staff=verifier, **tomorrow)) == "under_age"
    record.refresh_from_db()
    assert record.status == Status.SUBMITTED and record.full_name == ""
    assert not AdminAction.objects.filter(action__startswith="verification").exists()

    review.confirm_identity(record, staff=verifier, **identity_values(date_of_birth=date(2008, 11, 12)))
    record.refresh_from_db()
    assert record.status == Status.CONFIRMED


def test_expired_document_is_refused_and_one_expiring_today_is_accepted(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    yesterday = identity_values(document_expires_on=TODAY - timedelta(days=1))
    assert code(lambda: review.confirm_identity(record, staff=verifier, **yesterday)) == "document_expired"
    review.confirm_identity(record, staff=verifier, **identity_values(document_expires_on=TODAY))


def test_same_document_number_typed_differently_on_another_account_is_duplicate(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    second = send_identity(other_householder(), jpeg, seed=30)
    same = identity_values(document_number="ci001234567")
    assert code(lambda: review.confirm_identity(second, staff=verifier, **same)) == "duplicate_document"
    second.refresh_from_db()
    assert second.status == Status.SUBMITTED
    review.confirm_identity(second, staff=verifier, **identity_values(document_number="CI 999"))


def test_blank_recorded_fields_are_refused(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    for field in ("full_name", "document_number"):
        blank = identity_values(**{field: "   "})
        assert code(lambda blank=blank: review.confirm_identity(record, staff=verifier, **blank)) == (
            "field_required"
        )


def test_refuse_needs_a_reason_and_shows_it_in_the_checklist(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    assert code(lambda: review.refuse_identity(record, staff=verifier, reason="  ")) == "reason_required"
    review.refuse_identity(record, staff=verifier, reason="Photo floue, reprenez le recto.")
    assert checklist(householder)["identity"] == {
        "status": "refused",
        "reason": "Photo floue, reprenez le recto.",
    }
    action = AdminAction.objects.get(action="verification.identity.refuse")
    assert action.reason == "Photo floue, reprenez le recto."
    send_identity(householder, jpeg, seed=40)  # the step can start again


def test_second_decision_is_invalid_state_with_one_audit_row(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    stale = IdentityVerification.objects.get(pk=record.pk)  # what a second staff member still sees
    review.confirm_identity(record, staff=verifier, **identity_values())
    assert code(lambda: review.refuse_identity(stale, staff=verifier, reason="x")) == "invalid_state"
    assert (
        code(lambda: review.confirm_identity(stale, staff=verifier, **identity_values())) == "invalid_state"
    )
    stale.refresh_from_db()
    assert stale.status == Status.CONFIRMED
    assert AdminAction.objects.filter(action__startswith="verification.identity").count() == 1


def test_staff_without_permission_and_non_staff_are_forbidden(householder, jpeg, staff_user, verifier):
    record = send_identity(householder, jpeg)
    proof = send_address(householder, jpeg)
    inactive = User.objects.create_user(username="gone", password="pw", role="staff", is_staff=True)
    inactive.groups.set(verifier.groups.all())
    inactive.is_active = False
    inactive.save()
    for actor in (staff_user, householder, inactive, None):
        assert (
            code(lambda a=actor: review.confirm_identity(record, staff=a, **identity_values())) == "forbidden"
        )
        assert code(lambda a=actor: review.refuse_identity(record, staff=a, reason="x")) == "forbidden"
        assert code(lambda a=actor: review.confirm_address(proof, staff=a, **address_values())) == "forbidden"
        assert code(lambda a=actor: review.refuse_address(proof, staff=a, reason="x")) == "forbidden"
        assert code(lambda a=actor: review.read_photo(record.front, staff=a)) == "forbidden"
        assert code(lambda a=actor: review.open_for_review(record, staff=a)) == "forbidden"
    assert not AdminAction.objects.filter(action__startswith="verification").exists()


def test_confirm_address_requires_confirmed_identity_location_and_both_checks(householder, jpeg, verifier):
    proof = send_address(householder, jpeg)
    confirm = lambda **kw: review.confirm_address(proof, staff=verifier, **address_values(**kw))  # noqa: E731

    assert code(confirm) == "identity_not_confirmed"
    confirmed_identity(householder, jpeg, verifier)
    assert code(confirm) == "location_missing"
    send_location(householder)
    assert code(lambda: confirm(name_matches=False)) == "checks_required"
    assert code(lambda: confirm(address_consistent=False)) == "checks_required"
    assert code(lambda: confirm(holder_name=" ")) == "field_required"
    assert code(lambda: confirm(reference_number="")) == "field_required"

    proof.refresh_from_db()
    assert proof.status == Status.SUBMITTED and proof.holder_name == ""
    assert not AdminAction.objects.filter(action__startswith="verification.address").exists()


def test_proof_issued_more_than_three_months_ago_or_in_the_future_is_refused(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    send_location(householder)
    proof = send_address(householder, jpeg)
    confirm = lambda issued: review.confirm_address(  # noqa: E731
        proof, staff=verifier, **address_values(issued_on=issued)
    )
    assert code(lambda: confirm(date(2026, 8, 11))) == "proof_too_old"
    assert code(lambda: confirm(TODAY + timedelta(days=1))) == "proof_too_old"
    confirm(date(2026, 8, 12))  # exactly three months


def test_confirm_address_confirms_location_and_account_becomes_h1(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    location = send_location(householder)
    proof = send_address(householder, jpeg)
    assert householder_tier(householder) == "H0"

    review.confirm_address(proof, staff=verifier, **address_values())

    proof.refresh_from_db()
    location.refresh_from_db()
    assert proof.status == Status.CONFIRMED and location.status == Status.CONFIRMED
    assert proof.confirmed_at == timezone.now()
    assert proof.expires_at.date() == date(2027, 11, 12)
    assert "Kouassi" not in proof.holder_name and "889900" not in proof.reference_number
    assert decrypt_text(proof.reference_number) == "CIE-889900"
    assert householder_tier(householder) == "H1"
    assert checklist(householder)["home_location"]["status"] == "confirmed"
    assert AdminAction.objects.filter(action="verification.address.confirm").count() == 1


def test_duplicate_reference_number_is_refused(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    send_location(householder)
    review.confirm_address(send_address(householder, jpeg), staff=verifier, **address_values())

    other = other_householder()
    confirmed_identity(other, jpeg, verifier, seed=30, document_number="CI 999")
    send_location(other)
    proof = send_address(other, jpeg, seed=50)
    same = address_values(reference_number="cie 889900")
    assert code(lambda: review.confirm_address(proof, staff=verifier, **same)) == "duplicate_reference"
    assert householder_tier(other) == "H0"


def test_refuse_address_can_refuse_the_location_too(householder, jpeg, verifier):
    location = send_location(householder)
    proof = send_address(householder, jpeg)
    review.refuse_address(proof, staff=verifier, reason="Facture illisible")
    location.refresh_from_db()
    assert location.status == Status.SUBMITTED

    proof = send_address(householder, jpeg, seed=60)
    review.refuse_address(proof, staff=verifier, reason="Position loin du quartier", refuse_location=True)
    result = checklist(householder)
    assert result["address"]["status"] == "refused"
    assert result["home_location"] == {"status": "refused", "reason": "Position loin du quartier"}
    send_location(householder)  # both steps can start again
    send_address(householder, jpeg, seed=61)


def test_location_cannot_be_replaced_after_address_is_confirmed(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    send_location(householder)
    send_location(householder, lat=5.36)  # allowed while undecided
    review.confirm_address(send_address(householder, jpeg), staff=verifier, **address_values())
    assert code(lambda: send_location(householder)) == "invalid_state"
    assert HomeLocation.objects.filter(user=householder, status=Status.CONFIRMED).count() == 1


def test_expiry_task_returns_account_to_h0_and_step_can_restart(householder, jpeg, verifier):
    confirmed_identity(householder, jpeg, verifier)
    send_location(householder)
    review.confirm_address(send_address(householder, jpeg), staff=verifier, **address_values())

    with freeze_time("2027-11-12 09:59:00"):
        assert expire_address_proofs() == 0 and householder_tier(householder) == "H1"
    with freeze_time("2027-11-12 10:00:01"):
        assert expire_address_proofs() == 1
        assert householder_tier(householder) == "H0"
        result = checklist(householder)
        assert result["address"]["status"] == "expired" and result["home_location"]["status"] == "expired"
        assert result["identity"]["status"] == "confirmed"
        send_location(householder)
        send_address(householder, jpeg, seed=70)
        assert expire_address_proofs() == 0


def test_read_photo_needs_permission_and_audits_every_view(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    assert review.read_photo(record.front, staff=verifier) == jpeg(0)
    assert review.read_photo(record.front, staff=verifier) == jpeg(0)
    views = AdminAction.objects.filter(action="verification.view_photo")
    assert views.count() == 2 and all(v.target_id == str(record.front.pk) for v in views)

    verifier.groups.clear()
    reviewer_only = User.objects.get(pk=verifier.pk)
    assert code(lambda: review.read_photo(record.front, staff=reviewer_only)) == "forbidden"
    assert views.count() == 2


def test_open_for_review_moves_submitted_to_in_review_once(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    location = send_location(householder)
    proof = send_address(householder, jpeg)

    review.open_for_review(record, staff=verifier)
    review.open_for_review(record, staff=verifier)
    record.refresh_from_db()
    assert record.status == Status.IN_REVIEW
    assert AdminAction.objects.filter(action="verification.identity.open").count() == 1

    review.open_for_review(proof, staff=verifier)
    proof.refresh_from_db()
    location.refresh_from_db()
    assert proof.status == Status.IN_REVIEW and location.status == Status.IN_REVIEW
    assert checklist(householder)["home_location"]["status"] == "in_review"

    review.confirm_identity(record, staff=verifier, **identity_values())
    review.open_for_review(record, staff=verifier)
    record.refresh_from_db()
    assert record.status == Status.CONFIRMED


def test_in_review_records_can_still_be_decided(householder, jpeg, verifier):
    record = send_identity(householder, jpeg)
    review.open_for_review(record, staff=verifier)
    review.refuse_identity(record, staff=verifier, reason="Document coupé")
    assert AddressProof.objects.count() == 0 and checklist(householder)["identity"]["status"] == "refused"
