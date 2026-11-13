import pytest

from apps.accounts.models import User
from apps.verification.models import BriefingCard, BriefingCompletion, BriefingPass
from apps.verification.services import briefing
from apps.verification.services.submissions import VerificationError

pytestmark = pytest.mark.django_db


@pytest.fixture
def jobber():
    return User.objects.create_user(phone="+2250505050505", role="jobber")


@pytest.fixture(autouse=True)
def only_two_cards():
    """Start from two known cards, not the seeded placeholders."""
    BriefingCard.objects.all().delete()
    BriefingCard.objects.create(
        title="Un", body="b", question="q1", choices=["x", "y"], correct_index=1, explanation="e1", position=1
    )
    BriefingCard.objects.create(
        title="Deux",
        body="b",
        question="q2",
        choices=["x", "y", "z"],
        correct_index=2,
        explanation="e2",
        position=2,
    )


def code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


def card(title):
    return BriefingCard.objects.get(title=title)


def test_cards_never_expose_the_answer(jobber):
    cards = briefing.briefing_cards(jobber)
    assert [c["title"] for c in cards] == ["Un", "Deux"]
    for item in cards:
        assert set(item) == {"id", "title", "body", "question", "choices", "answered"}
        assert item["answered"] is False


def test_wrong_answer_returns_explanation_and_stores_nothing(jobber):
    result = briefing.answer_card(jobber, card("Un").pk, 0)
    assert result == {"correct": False, "explanation": "e1", "complete": False}
    assert BriefingCompletion.objects.count() == 0


def test_correct_answer_is_stored_once(jobber):
    briefing.answer_card(jobber, card("Un").pk, 1)
    again = briefing.answer_card(jobber, card("Un").pk, 1)
    assert again["correct"] is True and again["complete"] is False
    assert BriefingCompletion.objects.filter(user=jobber).count() == 1
    assert briefing.briefing_cards(jobber)[0]["answered"] is True


def test_all_cards_correct_creates_the_pass(jobber):
    briefing.answer_card(jobber, card("Un").pk, 1)
    last = briefing.answer_card(jobber, card("Deux").pk, 2)
    assert last["complete"] is True
    assert BriefingPass.objects.filter(user=jobber).exists()
    assert briefing.briefing_progress(jobber) == {
        "status": "confirmed",
        "reason": "",
        "answered": 2,
        "total": 2,
        "new_cards": 0,
    }


def test_progress_starts_empty_then_in_progress(jobber):
    assert briefing.briefing_progress(jobber)["status"] == "not_started"
    briefing.answer_card(jobber, card("Un").pk, 1)
    progress = briefing.briefing_progress(jobber)
    assert progress["status"] == "in_progress" and progress["answered"] == 1


def test_card_added_after_pass_keeps_confirmed_and_counts_as_new(jobber):
    briefing.answer_card(jobber, card("Un").pk, 1)
    briefing.answer_card(jobber, card("Deux").pk, 2)
    BriefingCard.objects.create(
        title="Trois",
        body="b",
        question="q3",
        choices=["x", "y"],
        correct_index=0,
        explanation="e3",
        position=3,
    )
    progress = briefing.briefing_progress(jobber)
    assert progress["status"] == "confirmed"
    assert progress["new_cards"] == 1 and progress["total"] == 3 and progress["answered"] == 2


def test_no_active_cards_never_confirms(jobber):
    BriefingCard.objects.update(active=False)
    progress = briefing.briefing_progress(jobber)
    assert progress["status"] == "not_started" and progress["total"] == 0
    assert not BriefingPass.objects.exists()


def test_deactivating_the_last_unanswered_card_completes_on_next_progress(jobber):
    briefing.answer_card(jobber, card("Un").pk, 1)
    BriefingCard.objects.filter(title="Deux").update(active=False)
    assert briefing.briefing_progress(jobber)["status"] == "confirmed"
    assert BriefingPass.objects.filter(user=jobber).exists()


def test_inactive_card_unknown_card_and_bad_choice_refused(jobber):
    BriefingCard.objects.filter(title="Deux").update(active=False)
    assert code(lambda: briefing.answer_card(jobber, card("Deux").pk, 2)) == "card_invalid"
    assert code(lambda: briefing.answer_card(jobber, "not-a-uuid", 0)) == "card_invalid"
    assert code(lambda: briefing.answer_card(jobber, card("Un").pk, 2)) == "choice_invalid"
    assert code(lambda: briefing.answer_card(jobber, card("Un").pk, -1)) == "choice_invalid"
    assert code(lambda: briefing.answer_card(jobber, card("Un").pk, "1")) == "choice_invalid"


def test_householder_forbidden(householder):
    assert code(lambda: briefing.briefing_cards(householder)) == "forbidden"
    assert code(lambda: briefing.answer_card(householder, card("Un").pk, 1)) == "forbidden"
    assert code(lambda: briefing.briefing_progress(householder)) == "forbidden"
