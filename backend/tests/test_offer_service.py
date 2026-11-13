from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from django.utils import timezone
from freezegun import freeze_time

from apps.listings.models import Offer, OfferCategory
from apps.listings.services import offers
from apps.listings.services.offers import OfferError

pytestmark = pytest.mark.django_db

ABIDJAN = ZoneInfo("Africa/Abidjan")
# A Wednesday, 10:00 in Abidjan (UTC+0): tomorrow is a normal working day.
NOW = "2026-11-11 10:00:00"


def local(day_offset, hour, minute=0):
    """A start time on the day `day_offset` days after NOW, in Abidjan local time."""
    base = datetime(2026, 11, 11, tzinfo=ABIDJAN) + timedelta(days=day_offset)
    return base.replace(hour=hour, minute=minute).astimezone(UTC)


def code(call):
    with pytest.raises(OfferError) as caught:
        call()
    return caught.value.code


def draft(author, menage, **overrides):
    values = {
        "category_id": menage.pk,
        "duties": ["Dépoussiérer"],
        "starts_at": local(1, 9),
        "duration_minutes": 180,
        "pay_xof": 3000,
        "note": "",
    }
    values.update(overrides)
    return offers.create_draft(author, **values)


@pytest.fixture
def menage():
    return OfferCategory.objects.get(name="Ménage")


@pytest.fixture
def other_verified(db, jpeg):
    """A second householder at H1 (its own phone and address)."""
    from apps.accounts.models import User
    from tests.conftest import make_verified

    return make_verified(User.objects.create_user(phone="+2250707070707", role="householder"), jpeg)


def test_h0_householder_cannot_create_or_send(householder, menage):
    with freeze_time(NOW):
        assert code(lambda: draft(householder, menage)) == "verification_required"


def test_jobber_and_staff_are_forbidden(enrolled, staff_user, menage):
    with freeze_time(NOW):
        for user in (enrolled.device.user, staff_user):
            assert code(lambda user=user: draft(user, menage)) == "forbidden"


def test_draft_is_saved_with_no_place_and_no_flags(verified_householder, menage):
    with freeze_time(NOW):
        offer = draft(verified_householder, menage)
    assert offer.status == "draft" and offer.flags == [] and offer.commune == "" and offer.quartier == ""
    assert offer.category_name == ""  # copied only when sent


@pytest.mark.parametrize(
    ("hour", "minute", "duration", "accepted"),
    [
        (9, 0, 180, True),
        (6, 0, 120, True),  # the earliest start
        (5, 59, 120, False),
        (17, 0, 120, True),  # ends exactly at 19:00
        (17, 1, 120, False),  # ends at 19:01
    ],
)
def test_start_and_end_hours_at_their_boundaries(
    verified_householder, menage, hour, minute, duration, accepted
):
    with freeze_time(NOW):
        call = lambda: draft(  # noqa: E731
            verified_householder, menage, starts_at=local(1, hour, minute), duration_minutes=duration
        )
        if accepted:
            call()
        else:
            assert code(call) == "time_invalid"


def test_end_may_not_pass_the_latest_hour(verified_householder, menage):
    with freeze_time(NOW):
        draft(verified_householder, menage, starts_at=local(1, 16), duration_minutes=180)
        assert (
            code(lambda: draft(verified_householder, menage, starts_at=local(1, 17), duration_minutes=180))
            == "time_invalid"
        )
        assert (
            code(lambda: draft(verified_householder, menage, starts_at=local(1, 16, 1), duration_minutes=180))
            == "time_invalid"
        )


def test_past_and_too_far_dates_are_refused(verified_householder, menage):
    with freeze_time(NOW):
        assert (
            code(lambda: draft(verified_householder, menage, starts_at=timezone.now() - timedelta(hours=1)))
            == "time_invalid"
        )
        draft(verified_householder, menage, starts_at=local(30, 9))
        assert code(lambda: draft(verified_householder, menage, starts_at=local(31, 9))) == "time_invalid"


def test_duties_duration_pay_and_note_rules(verified_householder, menage):
    with freeze_time(NOW):
        cases = [
            ({"duties": []}, "duties_invalid"),
            ({"duties": ["Voler la voiture"]}, "duties_invalid"),
            ({"duties": ["Dépoussiérer", "Dépoussiérer"]}, "duties_invalid"),
            ({"duration_minutes": 90}, "duration_invalid"),
            ({"pay_xof": 999}, "pay_invalid"),
            ({"pay_xof": 100001}, "pay_invalid"),
            ({"note": "x" * 301}, "note_too_long"),
            ({"category_id": 999999}, "category_invalid"),
        ]
        for overrides, expected in cases:
            assert code(lambda o=overrides: draft(verified_householder, menage, **o)) == expected, overrides
    assert not Offer.objects.exists()


def test_send_first_offer_goes_to_review_with_first_offer_flag(verified_householder, menage):
    with freeze_time(NOW):
        offer = offers.send(draft(verified_householder, menage), user=verified_householder)
    assert offer.status == "in_review" and offer.flags == ["first_offer"]
    assert offer.sent_at is not None and offer.published_at is None


def test_send_copies_category_name_commune_and_quartier(verified_householder, menage):
    with freeze_time(NOW):
        offer = offers.send(draft(verified_householder, menage), user=verified_householder)
    assert offer.category_name == "Ménage"
    assert (offer.commune, offer.quartier) == ("Cocody", "Angré")


def test_second_clean_offer_is_published_at_once(verified_householder, menage):
    first = Offer.objects.create(
        author=verified_householder,
        category=menage,
        category_name="Ménage",
        duties=["Dépoussiérer"],
        starts_at=local(1, 9),
        duration_minutes=180,
        pay_xof=3000,
        status="published",
        sent_at=timezone.now(),
        published_at=timezone.now(),
    )
    with freeze_time(NOW):
        offer = offers.send(
            draft(verified_householder, menage, starts_at=local(2, 9)), user=verified_householder
        )
    assert offer.status == "published" and offer.flags == [] and offer.published_at is not None
    assert first.pk != offer.pk


def test_send_twice_is_invalid_state(verified_householder, menage):
    with freeze_time(NOW):
        offer = offers.send(draft(verified_householder, menage), user=verified_householder)
        assert code(lambda: offers.send(offer, user=verified_householder)) == "invalid_state"


def test_fourth_open_offer_is_too_many(verified_householder, menage):
    with freeze_time(NOW):
        for day in (1, 2, 3):
            offers.send(
                draft(verified_householder, menage, starts_at=local(day, 9)), user=verified_householder
            )
        fourth = draft(verified_householder, menage, starts_at=local(4, 9))
        assert code(lambda: offers.send(fourth, user=verified_householder)) == "too_many_offers"


def test_category_made_inactive_or_duty_removed_before_send_is_refused(verified_householder, menage):
    with freeze_time(NOW):
        waiting = draft(verified_householder, menage)
        OfferCategory.objects.filter(pk=menage.pk).update(active=False)
        assert code(lambda: offers.send(waiting, user=verified_householder)) == "category_invalid"

        OfferCategory.objects.filter(pk=menage.pk).update(active=True, duties=["Nettoyer les vitres"])
        assert code(lambda: offers.send(waiting, user=verified_householder)) == "duties_invalid"


def test_editing_the_category_later_does_not_change_a_sent_offer(verified_householder, menage):
    with freeze_time(NOW):
        offer = offers.send(draft(verified_householder, menage), user=verified_householder)
    OfferCategory.objects.filter(pk=menage.pk).update(name="Ménage général", duties=["Autre"])
    offer.refresh_from_db()
    assert offer.category_name == "Ménage" and offer.duties == ["Dépoussiérer"]


def test_only_drafts_can_be_updated_or_deleted(verified_householder, menage):
    with freeze_time(NOW):
        sent = offers.send(draft(verified_householder, menage), user=verified_householder)
        assert (
            code(lambda: offers.update_draft(sent, user=verified_householder, pay_xof=4000))
            == "invalid_state"
        )
        assert code(lambda: offers.delete_draft(sent, user=verified_householder)) == "invalid_state"
        kept = draft(verified_householder, menage, starts_at=local(5, 9))
        updated = offers.update_draft(kept, user=verified_householder, pay_xof=4500)
        assert updated.pay_xof == 4500
        offers.delete_draft(updated, user=verified_householder)
    assert not Offer.objects.filter(pk=kept.pk).exists()


def test_withdraw_from_each_allowed_status_and_not_from_refused(verified_householder, menage):
    with freeze_time(NOW):
        waiting = offers.send(draft(verified_householder, menage), user=verified_householder)
        assert offers.withdraw(waiting, user=verified_householder).status == "withdrawn"
        keep = draft(verified_householder, menage, starts_at=local(6, 9))
        assert offers.withdraw(keep, user=verified_householder).status == "withdrawn"
        refused = draft(verified_householder, menage, starts_at=local(7, 9))
        Offer.objects.filter(pk=refused.pk).update(status="refused")
        refused.refresh_from_db()
        assert code(lambda: offers.withdraw(refused, user=verified_householder)) == "invalid_state"


def test_another_householder_cannot_touch_the_offer(verified_householder, other_verified, menage):
    with freeze_time(NOW):
        offer = draft(verified_householder, menage)
        assert code(lambda: offers.update_draft(offer, user=other_verified, pay_xof=4000)) == "forbidden"
        assert code(lambda: offers.delete_draft(offer, user=other_verified)) == "forbidden"
        assert code(lambda: offers.send(offer, user=other_verified)) == "forbidden"
        assert code(lambda: offers.withdraw(offer, user=other_verified)) == "forbidden"
        assert code(lambda: offers.copy_as_draft(offer, user=other_verified)) == "forbidden"


def test_copy_as_draft_moves_the_date_to_the_future(verified_householder, menage):
    with freeze_time(NOW):
        original = offers.send(
            draft(verified_householder, menage, starts_at=local(1, 9)), user=verified_householder
        )
        offers.withdraw(original, user=verified_householder)
    with freeze_time("2026-11-13 12:00:00"):
        copy = offers.copy_as_draft(original, user=verified_householder)
    assert copy.status == "draft" and copy.pk != original.pk
    assert copy.duties == original.duties and copy.pay_xof == original.pay_xof
    assert copy.starts_at > timezone.now()
    assert copy.starts_at.astimezone(ABIDJAN).hour == 9


def test_visible_to_jobbers_hides_past_offers_before_tidy_runs(verified_householder, menage):
    with freeze_time(NOW):
        offers.send(draft(verified_householder, menage, starts_at=local(1, 9)), user=verified_householder)
    with freeze_time("2026-11-12 12:00:00"):
        # Published, but its start has passed: the periodic task has not run yet.
        Offer.objects.update(status="published", published_at=timezone.now())
        assert not offers.visible_to_jobbers().exists()


def test_tidy_closes_past_offers_and_withdraws_those_of_unverified_householders(
    verified_householder, other_verified, menage
):
    with freeze_time(NOW):
        future = draft(verified_householder, menage, starts_at=local(3, 9))
        past = draft(verified_householder, menage, starts_at=local(1, 9))
        lapsed = draft(other_verified, menage, starts_at=local(3, 9))
        Offer.objects.filter(pk__in=[future.pk, past.pk, lapsed.pk]).update(
            status="published", published_at=timezone.now()
        )
    # Other householder loses verification: their proof is no longer confirmed.
    from apps.verification.models import AddressProof

    AddressProof.objects.filter(user=other_verified).update(status="expired")

    with freeze_time("2026-11-12 12:00:00"):
        result = offers.tidy()
    past.refresh_from_db()
    future.refresh_from_db()
    lapsed.refresh_from_db()
    assert result == {"closed": 1, "withdrawn": 1, "expired": 0}
    assert past.status == "closed" and future.status == "published"
    assert lapsed.status == "withdrawn" and "vérifié" in lapsed.reason


def draft_for(author, note=""):
    """A draft for the next day, Ménage at 3 000 FCFA; used by other test modules."""
    menage = OfferCategory.objects.get(name="Ménage")
    return offers.create_draft(
        author,
        category_id=menage.pk,
        duties=["Dépoussiérer"],
        starts_at=local(1, 9),
        duration_minutes=180,
        pay_xof=3000,
        note=note,
    )
