import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.verification.models import (
    BriefingCard,
    BriefingCompletion,
    ContactStatus,
    TrustedContact,
)


@pytest.fixture
def jobber(db):
    return User.objects.create_user(phone="+2250707070707", role="jobber")


def _contact(user, phone_hash="h" * 64, status=ContactStatus.PENDING):
    return TrustedContact.objects.create(
        user=user,
        name="enc",
        phone="enc",
        phone_hash=phone_hash,
        relationship="parent",
        status=status,
        code_requested_at=timezone.now(),
    )


@pytest.mark.django_db(transaction=True)
def test_one_live_contact_per_phone(jobber):
    _contact(jobber)
    with pytest.raises(IntegrityError), transaction.atomic():
        _contact(jobber)


def test_a_replaced_contact_does_not_block_the_same_phone(jobber):
    _contact(jobber, status=ContactStatus.REPLACED)
    _contact(jobber)
    assert TrustedContact.objects.filter(user=jobber).count() == 2


def _card(**changes):
    values = {
        "title": "Titre",
        "body": "Texte",
        "question": "Question ?",
        "choices": ["a", "b", "c"],
        "correct_index": 1,
        "explanation": "Parce que.",
    }
    return BriefingCard(**{**values, **changes})


@pytest.mark.parametrize(
    "changes",
    [
        {"choices": ["a"]},
        {"choices": ["a", "b", "c", "d", "e"]},
        {"choices": ["a", " "]},
        {"choices": "a"},
        {"correct_index": 3},
    ],
)
def test_card_choices_and_correct_index_are_validated(db, changes):
    with pytest.raises(ValidationError):
        _card(**changes).full_clean()


def test_a_valid_card_passes(db):
    _card().full_clean()


def test_completion_unique_per_user_and_card(jobber):
    card = _card()
    card.save()
    BriefingCompletion.objects.create(user=jobber, card=card)
    with pytest.raises(IntegrityError), transaction.atomic():
        BriefingCompletion.objects.create(user=jobber, card=card)


def test_seeded_cards_and_group_exist(db):
    assert BriefingCard.objects.filter(active=True).count() == 3
    group = Group.objects.get(name="briefing_manager")
    codes = set(group.permissions.values_list("codename", flat=True))
    assert codes == {"add_briefingcard", "change_briefingcard", "delete_briefingcard", "view_briefingcard"}


def test_verification_agent_group_can_send_contact_codes(db):
    group = Group.objects.get(name="verification_agent")
    codes = set(group.permissions.values_list("codename", flat=True))
    assert {"send_contact_code", "view_trustedcontact"} <= codes
