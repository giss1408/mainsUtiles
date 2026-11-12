from datetime import UTC, datetime, timedelta
from html import unescape
from zoneinfo import ZoneInfo

import pytest
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone
from freezegun import freeze_time

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.listings.models import ModerationTerm, Offer, OfferCategory
from apps.listings.services import moderation
from apps.listings.services.moderation import ModerationError
from apps.verification.models import AddressProof

pytestmark = pytest.mark.django_db

ABIDJAN = ZoneInfo("Africa/Abidjan")
BASE = "/admin/listings"


def in_days(days, hour=9):
    today = datetime.now(ABIDJAN).date()
    local = datetime(today.year, today.month, today.day, hour, tzinfo=ABIDJAN) + timedelta(days=days)
    return local.astimezone(UTC)


def code(call):
    with pytest.raises(ModerationError) as caught:
        call()
    return caught.value.code


@pytest.fixture
def moderator(db):
    user = User.objects.create_user(username="moderator", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="offer_moderator"))
    return user


@pytest.fixture
def moderator_client(moderator):
    client = Client()
    client.force_login(moderator)
    return client


@pytest.fixture
def catalogue_client(db):
    user = User.objects.create_user(username="catalogue", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="catalogue_manager"))
    client = Client()
    client.force_login(user)
    return client


def review_offer(author, flags=("pay_high",), days=2, **overrides):
    category = OfferCategory.objects.get(name="Ménage")
    values = {
        "author": author,
        "category": category,
        "category_name": "Ménage",
        "duties": ["Dépoussiérer"],
        "starts_at": in_days(days),
        "duration_minutes": 180,
        "pay_xof": 3000,
        "note": "",
        "commune": "Cocody",
        "quartier": "Angré",
        "status": "in_review",
        "flags": list(flags),
        "sent_at": timezone.now(),
    }
    values.update(overrides)
    return Offer.objects.create(**values)


def test_publish_makes_the_offer_visible_to_jobbers_and_audits(verified_householder, moderator):
    offer = review_offer(verified_householder)
    moderation.publish(offer, staff=moderator)
    offer.refresh_from_db()
    assert offer.status == "published" and offer.published_at is not None and offer.moderated_by == moderator
    assert AdminAction.objects.filter(action="offer.publish", target_id=str(offer.pk)).count() == 1


def test_refuse_needs_a_reason_and_the_householder_sees_it(verified_householder, moderator):
    offer = review_offer(verified_householder)
    assert code(lambda: moderation.refuse(offer, staff=moderator, reason="  ")) == "reason_required"
    moderation.refuse(offer, staff=moderator, reason="Rémunération à revoir")
    offer.refresh_from_db()
    assert offer.status == "refused" and offer.reason == "Rémunération à revoir"
    assert AdminAction.objects.get(action="offer.refuse").reason == "Rémunération à revoir"


def test_second_decision_is_invalid_state_with_one_audit_row(verified_householder, moderator):
    offer = review_offer(verified_householder)
    seen_by_second = Offer.objects.get(pk=offer.pk)  # the second staff member opened the same offer
    moderation.publish(offer, staff=moderator)  # the first staff member decides
    assert code(lambda: moderation.refuse(seen_by_second, staff=moderator, reason="x")) == "invalid_state"
    assert code(lambda: moderation.publish(seen_by_second, staff=moderator)) == "invalid_state"
    assert AdminAction.objects.filter(action__startswith="offer.").count() == 1


def test_publishing_a_past_offer_is_refused(verified_householder, moderator):
    offer = review_offer(verified_householder, days=-1)  # Review Focus 3
    assert code(lambda: moderation.publish(offer, staff=moderator)) == "time_invalid"
    offer.refresh_from_db()
    assert offer.status == "in_review"


def test_publishing_for_a_householder_no_longer_verified_is_refused(verified_householder, moderator):
    offer = review_offer(verified_householder)
    AddressProof.objects.filter(user=verified_householder).update(status="expired")
    assert code(lambda: moderation.publish(offer, staff=moderator)) == "verification_required"


def test_staff_without_the_permission_are_forbidden(verified_householder, staff_user):
    offer = review_offer(verified_householder)
    for actor in (staff_user, None):
        assert code(lambda a=actor: moderation.publish(offer, staff=a)) == "forbidden"
        assert code(lambda a=actor: moderation.refuse(offer, staff=a, reason="x")) == "forbidden"
    assert not AdminAction.objects.filter(action__startswith="offer.").exists()


def test_moderator_sees_queue_and_review_page_with_french_flags(moderator_client, verified_householder):
    offer = review_offer(verified_householder, flags=("pay_high", "travel", "first_offer"))
    listing = moderator_client.get(f"{BASE}/offer/").content.decode()
    assert "Cocody" in listing and "En cours de vérification" in listing
    html = unescape(moderator_client.get(f"{BASE}/offer/{offer.pk}/change/").content.decode())
    assert "Rémunération très au-dessus de la catégorie." in html
    assert "Mention de voyage, de logement ou de l'étranger." in html
    assert "Première offre de ce compte." in html
    assert "Publier" in html and "Refuser" in html


def test_publish_and_refuse_through_the_forms(moderator_client, verified_householder):
    first = review_offer(verified_householder)
    moderator_client.post(f"{BASE}/offer/{first.pk}/publish/")
    first.refresh_from_db()
    assert first.status == "published"

    second = review_offer(verified_householder, days=3)
    moderator_client.post(f"{BASE}/offer/{second.pk}/refuse/", {"reason": "Pas assez de détails"})
    second.refresh_from_db()
    assert (second.status, second.reason) == ("refused", "Pas assez de détails")


def test_verification_agent_gets_403_on_offers(verifier_client, verified_householder):
    offer = review_offer(verified_householder)
    assert verifier_client.get(f"{BASE}/offer/").status_code == 403
    assert verifier_client.get(f"{BASE}/offer/{offer.pk}/change/").status_code == 403
    assert verifier_client.post(f"{BASE}/offer/{offer.pk}/publish/").status_code == 403


def test_decisions_via_get_are_405(moderator_client, verified_householder):
    offer = review_offer(verified_householder)
    for action in ("publish", "refuse"):
        assert moderator_client.get(f"{BASE}/offer/{offer.pk}/{action}/").status_code == 405


def test_offers_cannot_be_edited_added_or_deleted_in_admin(moderator_client, verified_householder):
    offer = review_offer(verified_householder)
    assert moderator_client.get(f"{BASE}/offer/add/").status_code == 403
    assert moderator_client.post(f"{BASE}/offer/{offer.pk}/delete/", {"post": "yes"}).status_code == 403
    moderator_client.post(f"{BASE}/offer/{offer.pk}/change/", {"status": "published"})
    offer.refresh_from_db()
    assert offer.status == "in_review"


def test_catalogue_manager_edits_a_category_with_one_value_per_line(catalogue_client):
    menage = OfferCategory.objects.get(name="Ménage")
    url = f"{BASE}/offercategory/{menage.pk}/change/"
    html = catalogue_client.get(url).content.decode()
    assert "Balayer et laver les sols" in html
    response = catalogue_client.post(
        url,
        {
            "name": "Ménage",
            "duties": "Balayer\nDépoussiérer\n",
            "durations_minutes": "120\n240\n",
            "suggested_pay_min": 2500,
            "suggested_pay_max": 6000,
            "active": "on",
            "position": 0,
        },
    )
    assert response.status_code == 302
    menage.refresh_from_db()
    assert menage.duties == ["Balayer", "Dépoussiérer"]
    assert menage.durations_minutes == [120, 240]
    assert (menage.suggested_pay_min, menage.suggested_pay_max) == (2500, 6000)


def test_bad_category_form_shows_errors_and_saves_nothing(catalogue_client):
    menage = OfferCategory.objects.get(name="Ménage")
    response = catalogue_client.post(
        f"{BASE}/offercategory/{menage.pk}/change/",
        {
            "name": "Ménage",
            "duties": "",
            "durations_minutes": "deux heures",
            "suggested_pay_min": 9000,
            "suggested_pay_max": 1000,
            "active": "on",
            "position": 0,
        },
    )
    assert response.status_code == 200
    menage.refresh_from_db()
    assert menage.duties[0] == "Balayer et laver les sols"


def test_moderator_cannot_edit_categories_or_terms(moderator_client):
    menage = OfferCategory.objects.get(name="Ménage")
    assert moderator_client.get(f"{BASE}/offercategory/{menage.pk}/change/").status_code == 403
    assert moderator_client.get(f"{BASE}/moderationterm/add/").status_code == 403


def test_a_new_term_flags_the_next_offer(verified_householder, catalogue_client, moderator):
    from apps.listings.services import offers as offer_service
    from tests.test_offer_service import draft_for

    catalogue_client.post(f"{BASE}/moderationterm/add/", {"text": "coiffeuse", "kind": "appearance"})
    assert ModerationTerm.objects.filter(text="coiffeuse").exists()
    with freeze_time("2026-11-11 10:00:00"):
        draft = draft_for(verified_householder, note="Une coiffeuse est demandée")
        sent = offer_service.send(draft, user=verified_householder)
    assert "appearance" in sent.flags and sent.status == "in_review"
