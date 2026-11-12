import pytest

from apps.listings.models import ModerationTerm, OfferCategory
from apps.listings.services.screening import normalise, screen

pytestmark = pytest.mark.django_db


@pytest.fixture
def menage():
    return OfferCategory.objects.get(name="Ménage")


def test_clean_offer_has_no_flags(menage):
    assert screen(category=menage, pay_xof=3000, note="Merci d'apporter des gants.", first_offer=False) == []


def test_pay_boundaries(menage):
    # Ménage: suggested 2000-5000, flagged above 2 x 5000 = 10000 and below 2000.
    assert screen(category=menage, pay_xof=10000, note="", first_offer=False) == []
    assert screen(category=menage, pay_xof=10001, note="", first_offer=False) == ["pay_high"]
    assert screen(category=menage, pay_xof=2000, note="", first_offer=False) == []
    assert screen(category=menage, pay_xof=1999, note="", first_offer=False) == ["pay_low"]


@pytest.mark.parametrize("note", ["Logée sur place", "LOGEE", "voyage a l'etranger", "à l'Étranger"])
def test_travel_terms_ignore_case_and_accents(menage, note):
    assert screen(category=menage, pay_xof=3000, note=note, first_offer=False) == ["travel"]


@pytest.mark.parametrize("note", ["contact WhatsApp", "whatsapp", "Appelez-moi"])
def test_off_platform_terms(menage, note):
    assert screen(category=menage, pay_xof=3000, note=note, first_offer=False) == ["off_platform"]


def test_terms_match_whole_words_only(menage):
    # "belle" must not match inside "poubelle".
    assert screen(category=menage, pay_xof=3000, note="sortir la poubelle", first_offer=False) == []
    assert screen(category=menage, pay_xof=3000, note="une belle maison", first_offer=False) == ["appearance"]


@pytest.mark.parametrize("note", ["07 08 09 10 11", "0708.09.10.11", "+225 0708091011", "a@b.ci"])
def test_contact_details_in_disguise(menage, note):
    # Review Focus 2: the spelled-out form is not detected and is accepted by design.
    assert screen(category=menage, pay_xof=3000, note=note, first_offer=False) == ["contact_details"]


def test_short_numbers_are_not_contact_details(menage):
    note = "3 pièces, 2 salles de bain, 4e étage"
    assert screen(category=menage, pay_xof=3000, note=note, first_offer=False) == []


def test_first_offer_flag_and_order(menage):
    flags = screen(category=menage, pay_xof=12000, note="voyage", first_offer=True)
    assert flags == ["pay_high", "travel", "first_offer"]


def test_a_term_added_in_the_database_is_used_at_once(menage):
    assert screen(category=menage, pay_xof=3000, note="coiffeuse", first_offer=False) == []
    ModerationTerm.objects.create(text="coiffeuse", kind="appearance")
    assert screen(category=menage, pay_xof=3000, note="coiffeuse", first_offer=False) == ["appearance"]


def test_normalise_removes_accents_and_case():
    assert normalise("  Étranger   ÉLU ") == "etranger elu"
