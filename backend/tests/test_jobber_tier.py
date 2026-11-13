from datetime import timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import Guarantor, IdentityVerification, Status
from apps.verification.services import review, submissions
from apps.verification.services.tiers import checklist, jobber_checklist, jobber_tier
from apps.verification.tasks import expire_guarantors
from tests.test_guarantor_review import call_done, confirm_values, new_jobber, sent

pytestmark = pytest.mark.django_db


def verified_jobber(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    record = sent(user, jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values(reference_number=f"R-{user.pk}"))
    return user, record


def test_tier_is_j0_until_all_required_steps_are_confirmed(jpeg, verifier):
    user = new_jobber(jpeg, verifier)  # identity confirmed only
    assert jobber_tier(user) == "J0"
    record = sent(user, jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values())
    assert jobber_tier(user) == "J1"


def test_the_required_steps_setting_changes_the_tier(jpeg, verifier, settings):
    user = new_jobber(jpeg, verifier)
    settings.JOBBER_REQUIRED_STEPS = ["identity"]
    assert jobber_tier(user) == "J1"
    settings.JOBBER_REQUIRED_STEPS = ["identity", "guarantor"]
    assert jobber_tier(user) == "J0"


def test_an_expired_guarantor_drops_to_j0_and_can_be_resubmitted(jpeg, verifier):
    user, record = verified_jobber(jpeg, verifier)
    assert jobber_tier(user) == "J1"
    Guarantor.objects.filter(pk=record.pk).update(expires_at=timezone.now() - timedelta(days=1))
    assert jobber_tier(user) == "J0"
    assert jobber_checklist(user)["guarantor"]["status"] == "expired"
    assert submissions.expire_guarantors(user) == 1
    assert sent(user, jpeg, document_type="facture_eau").status == Status.SUBMITTED


def test_checklist_has_statuses_only(jpeg, verifier):
    user, record = verified_jobber(jpeg, verifier)
    data = jobber_checklist(user)
    assert set(data) == {"tier", "review_hours", "required", "identity", "guarantor"}
    assert set(data["guarantor"]) == {"status", "reason"}
    text = repr(data)
    for secret in ("Kouassi", "0707", "CIE-5566", str(record.photo.storage_name)):
        assert secret not in text


def test_refused_reason_is_shown(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    record = sent(user, jpeg)
    review.refuse_guarantor(record, staff=verifier, reason="Facture illisible.")
    assert jobber_checklist(user)["guarantor"] == {"status": "refused", "reason": "Facture illisible."}


def test_the_expire_task_sweeps_overdue_guarantors(jpeg, verifier):
    _, record = verified_jobber(jpeg, verifier)
    Guarantor.objects.filter(pk=record.pk).update(expires_at=timezone.now() - timedelta(days=1))
    assert expire_guarantors() == 1
    record.refresh_from_db()
    assert record.status == Status.EXPIRED


def test_householder_tier_is_unchanged(householder):
    assert checklist(householder)["tier"] == "H0"
    assert jobber_tier(householder) == "J0"
    assert IdentityVerification.objects.count() == 0
    assert User.objects.filter(role="jobber").count() == 0
