"""The safety briefing: cards written by staff, answered in the app. No review: a correct answer
to every active card completes it. The pass is kept, so a card added later does not undo it."""

from django.core.exceptions import ValidationError
from django.db import transaction

from apps.verification.models import BriefingCard, BriefingCompletion, BriefingPass

from .submissions import VerificationError, _require_jobber


def _active():
    return BriefingCard.objects.filter(active=True)


def _answered_ids(user) -> set:
    return set(
        BriefingCompletion.objects.filter(user=user, card__active=True).values_list("card_id", flat=True)
    )


def briefing_cards(user) -> list[dict]:
    """The active cards in order. Never the right answer or the explanation."""
    _require_jobber(user)
    answered = _answered_ids(user)
    return [
        {
            "id": str(card.pk),
            "title": card.title,
            "body": card.body,
            "question": card.question,
            "choices": list(card.choices),
            "answered": card.pk in answered,
        }
        for card in _active()
    ]


def sync_pass(user) -> bool:
    """Create the pass once every active card is answered correctly. Idempotent."""
    if BriefingPass.objects.filter(user=user).exists():
        return True
    total = _active().count()
    if total and len(_answered_ids(user)) == total:
        BriefingPass.objects.get_or_create(user=user)
        return True
    return False


def answer_card(user, card_id, choice) -> dict:
    """Check one answer. A wrong one stores nothing and shows the explanation."""
    _require_jobber(user)
    try:
        card = _active().filter(pk=card_id).first()
    except (ValidationError, ValueError):
        card = None
    if card is None:
        raise VerificationError("card_invalid")
    if isinstance(choice, bool) or not isinstance(choice, int) or not 0 <= choice < len(card.choices):
        raise VerificationError("choice_invalid")
    correct = choice == card.correct_index
    with transaction.atomic():
        if correct:
            BriefingCompletion.objects.get_or_create(user=user, card=card)
        complete = sync_pass(user)
    return {"correct": correct, "explanation": card.explanation, "complete": complete}


def briefing_progress(user) -> dict:
    _require_jobber(user)
    passed = sync_pass(user)
    total = _active().count()
    answered = len(_answered_ids(user))
    if passed:
        status = "confirmed"
    else:
        status = "in_progress" if answered else "not_started"
    return {
        "status": status,
        "reason": "",
        "answered": answered,
        "total": total,
        "new_cards": total - answered,
    }
