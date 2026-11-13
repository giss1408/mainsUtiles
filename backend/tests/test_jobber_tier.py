from datetime import timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import (
    BriefingCard,
    ContactStatus,
    Guarantor,
    IdentityVerification,
    Status,
    TrustedContact,
)
from apps.verification.services import contacts, review, submissions
from apps.verification.services.tiers import checklist, jobber_checklist, jobber_tier
from apps.verification.tasks import expire_guarantors
from tests.helpers import confirm_contact_and_briefing
from tests.test_guarantor_review import call_done, confirm_values, new_jobber, sent

pytestmark = pytest.mark.django_db


def verified_jobber(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    record = sent(user, jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values(reference_number=f"R-{user.pk}"))
    confirm_contact_and_briefing(user, verifier)
    return user, record


def test_tier_is_j0_until_all_required_steps_are_confirmed(jpeg, verifier):
    user = new_jobber(jpeg, verifier)  # identity confirmed only
    assert jobber_tier(user) == "J0"
    record = sent(user, jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values())
    assert jobber_tier(user) == "J0"  # the contact and the briefing are still missing


def test_j1_needs_all_four_steps(jpeg, verifier):
    user, _ = verified_jobber(jpeg, verifier)
    assert jobber_tier(user) == "J1"
    TrustedContact.objects.filter(user=user).delete()
    assert jobber_tier(user) == "J0"
    confirm_contact = contacts.add_contact(user, name="Yao", phone="01 02 03 04 05", relationship="friend")
    contacts.confirm_contact(user, confirm_contact.pk, contacts.send_code(confirm_contact, staff=verifier))
    assert jobber_tier(user) == "J1"
    from apps.verification.models import BriefingPass

    BriefingPass.objects.filter(user=user).delete()
    BriefingCard.objects.update(active=False)  # nothing to answer never grants the step
    assert jobber_tier(user) == "J0"


def test_a_pending_contact_does_not_count(jpeg, verifier):
    user, _ = verified_jobber(jpeg, verifier)
    TrustedContact.objects.filter(user=user).delete()
    contacts.add_contact(user, name="Yao", phone="01 02 03 04 05", relationship="friend")
    assert jobber_tier(user) == "J0"
    assert jobber_checklist(user)["trusted_contact"]["status"] == "in_progress"


def test_replacing_a_contact_never_drops_the_tier(jpeg, verifier):
    user, _ = verified_jobber(jpeg, verifier)
    old = TrustedContact.objects.get(user=user, status=ContactStatus.CONFIRMED)
    new = contacts.replace_contact(user, old.pk, name="Yao", phone="01 02 03 04 05", relationship="friend")
    assert jobber_tier(user) == "J1"  # the old one counts while the new one is pending
    contacts.confirm_contact(user, new.pk, contacts.send_code(new, staff=verifier))
    contacts.record_notice(old, staff=verifier)
    TrustedContact.objects.filter(pk=old.pk).update(old_notified_at=timezone.now() - timedelta(hours=80))
    assert jobber_tier(user) == "J1"  # the checklist sweeps the swap, the new one counts
    old.refresh_from_db()
    assert old.status == ContactStatus.REPLACED
    assert jobber_checklist(user)["trusted_contact"]["confirmed"] == 1


def test_a_new_card_after_j1_keeps_j1(jpeg, verifier):
    user, _ = verified_jobber(jpeg, verifier)
    BriefingCard.objects.create(
        title="Nouvelle", body="b", question="q", choices=["x", "y"], correct_index=0, explanation="e"
    )
    assert jobber_tier(user) == "J1"
    assert jobber_checklist(user)["briefing"]["new_cards"] == 1


def test_the_required_steps_setting_changes_the_tier(jpeg, verifier, settings):
    user = new_jobber(jpeg, verifier)
    settings.JOBBER_REQUIRED_STEPS = ["identity"]
    assert jobber_tier(user) == "J1"
    settings.JOBBER_REQUIRED_STEPS = ["identity", "guarantor"]
    assert jobber_tier(user) == "J0"
    settings.JOBBER_REQUIRED_STEPS = ["identity", "unknown_step"]
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
    assert set(data) == {
        "tier",
        "review_hours",
        "required",
        "identity",
        "guarantor",
        "trusted_contact",
        "briefing",
    }
    assert set(data["guarantor"]) == {"status", "reason"}
    assert set(data["trusted_contact"]) == {"status", "reason", "confirmed", "pending"}
    assert set(data["briefing"]) == {"status", "reason", "answered", "total", "new_cards"}
    text = repr(data)
    for secret in ("Kouassi", "0707", "Awa", "0101", "correct_index", str(record.photo.storage_name)):
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
