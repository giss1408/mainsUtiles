import pytest
from django.contrib.auth.models import Group

from apps.accounts.models import User
from apps.verification.models import BriefingCard

pytestmark = pytest.mark.django_db

ADD = "/admin/verification/briefingcard/add/"
LIST = "/admin/verification/briefingcard/"


@pytest.fixture
def manager_client(client):
    user = User.objects.create_user(username="briefing", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="briefing_manager"))
    client.force_login(user)
    return client


def form(**overrides):
    values = {
        "title": "Nouvelle carte",
        "body": "Un texte.",
        "question": "Que fais-tu ?",
        "choices": "Je reste\nJe pars\nJe me tais",
        "correct_index": "2",
        "explanation": "Parce que.",
        "position": "5",
        "active": "on",
    }
    values.update(overrides)
    return values


def test_manager_creates_a_card_from_lines_and_a_number(manager_client):
    response = manager_client.post(ADD, form())
    assert response.status_code == 302
    card = BriefingCard.objects.get(title="Nouvelle carte")
    assert card.choices == ["Je reste", "Je pars", "Je me tais"]
    assert card.correct_index == 1  # shown to staff as line number 2


def test_editing_shows_the_one_based_line_number_and_one_choice_per_line(manager_client):
    card = BriefingCard.objects.get(title="Avant de partir")
    page = manager_client.get(f"/admin/verification/briefingcard/{card.pk}/change/").content.decode()
    assert "Je préviens ma personne de confiance" in page
    assert 'name="correct_index"' in page and 'value="2"' in page


@pytest.mark.parametrize(
    "changes, message",
    [
        ({"choices": "Un seul"}, "Indiquez de 2 à 4 choix."),
        ({"choices": "a\nb\nc\nd\ne"}, "Indiquez de 2 à 4 choix."),
        ({"correct_index": "9"}, "La bonne réponse doit être l&#x27;un des choix."),
        ({"correct_index": "0"}, "La bonne réponse doit être l&#x27;un des choix."),
        ({"correct_index": "x"}, "Entrez un nombre entier."),
    ],
)
def test_an_invalid_card_shows_french_errors_and_is_not_saved(manager_client, changes, message):
    response = manager_client.post(ADD, form(**changes))
    assert response.status_code == 200 and message in response.content.decode()
    assert not BriefingCard.objects.filter(title="Nouvelle carte").exists()


def test_toggle_active_and_position_in_the_list(manager_client):
    card = BriefingCard.objects.get(title="Tu peux partir")
    data = {
        "form-TOTAL_FORMS": "3",
        "form-INITIAL_FORMS": "3",
        "form-MIN_NUM_FORMS": "0",
        "form-MAX_NUM_FORMS": "1000",
        "_save": "Enregistrer",
    }
    for index, item in enumerate(BriefingCard.objects.order_by("position", "title")):
        data[f"form-{index}-id"] = str(item.pk)
        data[f"form-{index}-position"] = "9" if item.pk == card.pk else str(item.position)
        if item.pk != card.pk:
            data[f"form-{index}-active"] = "on"
    manager_client.post(LIST, data)
    card.refresh_from_db()
    assert card.active is False and card.position == 9


def test_a_verification_agent_without_the_group_gets_403(verifier_client):
    assert verifier_client.get(LIST).status_code == 403
    assert verifier_client.get(ADD).status_code == 403
