"""Regressions found by the review of the jobber verification branch."""

from datetime import timedelta

import pytest
from django.conf import settings
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient

from apps.verification.models import BriefingCard, BriefingCompletion, BriefingPass, Guarantor, TrustedContact
from apps.verification.services import briefing, contacts, review, submissions
from apps.verification.services.submissions import VerificationError
from apps.verification.services.tiers import jobber_checklist, jobber_tier
from tests.test_guarantor_review import call_done, confirm_values, new_jobber, sent
from tests.test_jobber_tier import verified_jobber

pytestmark = pytest.mark.django_db

NUMBER = "01 01 01 01 01"


def test_a_guarantor_cannot_be_one_of_the_jobbers_live_contacts(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    contacts.add_contact(user, name="Awa", phone=NUMBER, relationship="parent")
    with pytest.raises(VerificationError) as caught:
        submissions.submit_guarantor(
            user,
            document_type=settings.GUARANTOR_DOCUMENT_TYPES[0],
            photo=jpeg,
            guarantor_name="Awa",
            guarantor_phone="+225 01 01 01 01 01",
            relationship="parent",
            captured_at=timezone.now(),
        )
    assert caught.value.code == "guarantor_phone_contact"


def test_an_expired_guarantor_costs_j1_without_waiting_for_the_sweep(jpeg, verifier):
    user, record = verified_jobber(jpeg, verifier)
    assert jobber_tier(user) == "J1"
    Guarantor.objects.filter(pk=record.pk).update(expires_at=timezone.now() - timedelta(minutes=1))
    assert jobber_tier(user) == "J0"
    assert jobber_checklist(user)["guarantor"]["status"] == "expired"
    assert Guarantor.objects.get(pk=record.pk).status == "expired"


def test_the_checklist_settles_once_and_stays_light(jpeg, verifier):
    user, _ = verified_jobber(jpeg, verifier)
    with CaptureQueriesContext(connection) as ctx:
        jobber_checklist(user)
    updates = [q for q in ctx.captured_queries if q["sql"].lstrip().upper().startswith("UPDATE")]
    assert len(updates) <= 2  # one sweep for contacts, one for guarantors
    assert len(ctx) <= 14


def test_a_code_is_sent_only_after_the_jobber_asked_and_only_once(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    contact = contacts.add_contact(user, name="Awa", phone=NUMBER, relationship="parent")
    code = contacts.send_code(contact, staff=verifier)
    with pytest.raises(VerificationError) as caught:  # a double tap or a replay
        contacts.send_code(contact, staff=verifier)
    assert caught.value.code == "invalid_state"
    assert contacts.confirm_contact(user, contact.pk, code).status == "confirmed"


def test_a_new_code_follows_a_new_request(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    contact = contacts.add_contact(user, name="Awa", phone=NUMBER, relationship="parent")
    contacts.send_code(contact, staff=verifier)
    aged = timezone.now() - timedelta(hours=1)
    TrustedContact.objects.filter(pk=contact.pk).update(code_sent_at=aged, code_requested_at=aged)
    contacts.request_code(user, contact.pk)
    assert contacts.send_code(contact, staff=verifier)


def test_a_failed_link_gives_the_code_back(jpeg, verifier, monkeypatch):
    from apps.verification.api import staff_views

    user = new_jobber(jpeg, verifier)
    contact = contacts.add_contact(user, name="Awa", phone=NUMBER, relationship="parent")

    def boom():
        raise RuntimeError("messaging down")

    monkeypatch.setattr(staff_views.registry, "get_messaging", boom)
    client = APIClient(raise_request_exception=False)
    client.force_authenticate(verifier)
    assert client.post(f"/api/v1/staff/contacts/{contact.pk}/send").status_code == 500
    contact.refresh_from_db()
    assert contact.code_sent_at is None and contact.code_hash == ""
    assert contacts.awaiting_code(contact)


def test_confirming_a_guarantor_takes_the_lock_that_serialises_the_bill_cap(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    record = sent(user, jpeg)
    call_done(record, verifier)
    with CaptureQueriesContext(connection) as ctx:
        review.confirm_guarantor(record, staff=verifier, **confirm_values())
    assert any("pg_advisory_xact_lock" in q["sql"] for q in ctx.captured_queries)


def test_staff_open_only_contacts_that_are_in_a_queue(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    contact = contacts.add_contact(user, name="Awa", phone=NUMBER, relationship="parent")
    client = APIClient()
    client.force_authenticate(verifier)
    assert client.get(f"/api/v1/staff/contacts/{contact.pk}").status_code == 200
    contacts.confirm_contact(user, contact.pk, contacts.send_code(contact, staff=verifier))
    assert client.get(f"/api/v1/staff/contacts/{contact.pk}").status_code == 404


def _passed(user):
    for card in briefing.briefing_cards(user):
        briefing.answer_card(user, card["id"], BriefingCard.objects.get(pk=card["id"]).correct_index)


def test_changing_a_cards_answer_key_withdraws_the_credit_and_the_pass(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    _passed(user)
    assert BriefingPass.objects.filter(user=user).exists()
    card = BriefingCard.objects.filter(active=True).first()
    card.correct_index = (card.correct_index + 1) % len(card.choices)
    card.save()
    assert not BriefingCompletion.objects.filter(user=user, card=card).exists()
    assert not BriefingPass.objects.filter(user=user).exists()
    assert briefing.briefing_progress(user)["status"] == "in_progress"


def test_a_wording_fix_keeps_the_credit(jpeg, verifier):
    user = new_jobber(jpeg, verifier)
    _passed(user)
    card = BriefingCard.objects.filter(active=True).first()
    card.explanation = card.explanation + " (précision)"
    card.save()
    assert BriefingPass.objects.filter(user=user).exists()
    assert BriefingCompletion.objects.filter(user=user, card=card).exists()
