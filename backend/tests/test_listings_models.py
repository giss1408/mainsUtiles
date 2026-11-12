from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.utils import timezone

from apps.accounts.models import User
from apps.listings.models import ModerationTerm, Offer, OfferCategory
from apps.listings.services.catalogue import active_categories

pytestmark = pytest.mark.django_db


def test_seeded_categories_have_the_spec_values():
    names = list(OfferCategory.objects.values_list("name", flat=True))
    assert names == ["Ménage", "Cuisine", "Accompagnement d'une personne âgée"]
    menage = OfferCategory.objects.get(name="Ménage")
    assert menage.durations_minutes == [120, 180, 240]
    assert (menage.suggested_pay_min, menage.suggested_pay_max) == (2000, 5000)
    assert "Balayer et laver les sols" in menage.duties and len(menage.duties) == 5
    cuisine = OfferCategory.objects.get(name="Cuisine")
    assert cuisine.durations_minutes == [120, 180] and len(cuisine.duties) == 3
    care = OfferCategory.objects.get(name="Accompagnement d'une personne âgée")
    assert care.durations_minutes == [120, 240, 480]
    assert (care.suggested_pay_min, care.suggested_pay_max) == (3000, 8000)
    assert all(c.active for c in OfferCategory.objects.all())


def test_seeded_terms_cover_the_four_kinds():
    kinds = set(ModerationTerm.objects.values_list("kind", flat=True))
    assert kinds == {"appearance", "travel", "empty_home", "off_platform"}
    texts = set(ModerationTerm.objects.values_list("text", flat=True))
    assert {"jeune fille", "nourri logé", "maison vide", "WhatsApp"} <= texts


def test_category_clean_refuses_empty_duties_bad_durations_and_inverted_pay():
    def category(**overrides):
        values = {
            "name": "Jardin",
            "duties": ["Arroser"],
            "durations_minutes": [120],
            "suggested_pay_min": 1000,
            "suggested_pay_max": 2000,
        }
        values.update(overrides)
        return OfferCategory(**values)

    category().full_clean()
    for bad in (
        {"duties": []},
        {"duties": ["Arroser", "  "]},
        {"durations_minutes": []},
        {"durations_minutes": [0]},
        {"durations_minutes": ["deux heures"]},
        {"suggested_pay_min": 3000},
    ):
        with pytest.raises(ValidationError):
            category(**bad).full_clean()


def test_inactive_categories_are_left_out_of_active_categories():
    OfferCategory.objects.filter(name="Cuisine").update(active=False)
    assert [c.name for c in active_categories()] == ["Ménage", "Accompagnement d'une personne âgée"]


def test_groups_have_their_permissions():
    def codenames(group):
        return set(Group.objects.get(name=group).permissions.values_list("codename", flat=True))

    assert {"moderate_offer", "view_offer"} <= codenames("offer_moderator")
    assert "change_offercategory" not in codenames("offer_moderator")
    assert {
        "add_offercategory",
        "change_offercategory",
        "delete_offercategory",
        "view_offercategory",
        "add_moderationterm",
        "change_moderationterm",
        "delete_moderationterm",
        "view_moderationterm",
    } <= codenames("catalogue_manager")
    assert "moderate_offer" not in codenames("catalogue_manager")
    for other in ("enrolment_agent", "verification_agent"):
        assert not {"moderate_offer", "change_offercategory"} & codenames(other)


def test_offer_ends_at_and_default_status():
    author = User.objects.create_user(phone="+2250505050505", role="householder")
    menage = OfferCategory.objects.get(name="Ménage")
    start = timezone.now() + timedelta(days=1)
    offer = Offer.objects.create(
        author=author,
        category=menage,
        duties=["Dépoussiérer"],
        starts_at=start,
        duration_minutes=180,
        pay_xof=3000,
    )
    assert offer.status == "draft" and offer.flags == [] and offer.commune == ""
    assert offer.ends_at == start + timedelta(minutes=180)
    assert Offer.OPEN_STATUSES == ("in_review", "published")


def test_offer_settings_have_the_spec_defaults(settings):
    assert (settings.OFFER_EARLIEST_START, settings.OFFER_LATEST_END) == ("06:00", "19:00")
    assert (settings.OFFER_MIN_PAY_XOF, settings.OFFER_MAX_PAY_XOF) == (1000, 100000)
    assert settings.OFFER_PAY_FLAG_FACTOR == 2
    assert settings.OFFER_MAX_DAYS_AHEAD == 30 and settings.OFFER_MAX_OPEN_PER_HOUSEHOLDER == 3
    assert settings.OFFER_NOTE_MAX_LENGTH == 300 and settings.OFFER_REVIEW_HOURS == 24
