import threading
from datetime import timedelta

import pytest
from django.db import connection
from django.utils import timezone

from apps.audit.models import AdminAction
from apps.bookings.models import Application, Booking
from apps.bookings.services import applications
from apps.bookings.services.applications import BookingError
from apps.listings.models import Offer
from apps.listings.services import offers as offer_service
from apps.verification.models import Guarantor
from tests.helpers import j1_jobber, make_offer
from tests.test_booking_models import booking_for

pytestmark = pytest.mark.django_db


@pytest.fixture
def offer(verified_householder):
    return make_offer(verified_householder)


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def test_applicants_list_has_first_name_tier_and_message_and_nothing_else(
    offer, jobber, verified_householder
):
    applications.apply(jobber, offer.pk, "Je suis disponible.")
    rows = applications.applicants(verified_householder, offer.pk)
    assert len(rows) == 1
    row = rows[0]
    assert set(row) == {"id", "first_name", "tier", "jobs_done", "rating", "message", "created_at"}
    assert row["first_name"] == "Jeune" and row["tier"] == "J1"
    assert row["jobs_done"] == 0 and row["rating"] is None and row["message"] == "Je suis disponible."
    raw = str(rows)
    assert "Jobber" not in raw and jobber.phone not in raw and str(jobber.pk) not in raw


def test_applicants_are_oldest_first_and_only_pending(offer, verified_householder, jpeg, verifier):
    first = j1_jobber(jpeg, verifier)
    second = j1_jobber(jpeg, verifier)
    a = applications.apply(first, offer.pk, "")
    b = applications.apply(second, offer.pk, "")
    applications.withdraw(first, a.pk)
    assert [r["id"] for r in applications.applicants(verified_householder, offer.pk)] == [b.pk]


def test_only_the_owner_sees_applicants(offer, jobber):
    assert code(lambda: applications.applicants(jobber, offer.pk)) == "forbidden"


def test_accept_creates_one_booking_declines_the_others_and_books_the_offer(
    offer, verified_householder, jobber, jpeg, verifier
):
    other = j1_jobber(jpeg, verifier)
    chosen = applications.apply(jobber, offer.pk, "")
    rejected = applications.apply(other, offer.pk, "")
    booking = applications.accept(verified_householder, chosen.pk)
    assert booking.status == Booking.Status.ACCEPTED and booking.jobber == jobber
    assert (booking.category_name, booking.pay_xof, booking.commune, booking.quartier) == (
        "Ménage",
        3000,
        "Cocody",
        "Angré",
    )
    assert booking.duties == ["Dépoussiérer"] and booking.starts_at == offer.starts_at
    chosen.refresh_from_db()
    rejected.refresh_from_db()
    offer.refresh_from_db()
    assert chosen.status == Application.Status.ACCEPTED and rejected.status == Application.Status.DECLINED
    assert rejected.decided_at and offer.status == Offer.Status.BOOKED
    assert AdminAction.objects.filter(action="booking.accept", actor=verified_householder).exists()


def test_second_accept_is_invalid_state_and_one_booking_exists(
    offer, verified_householder, jobber, jpeg, verifier
):
    other = j1_jobber(jpeg, verifier)
    a = applications.apply(jobber, offer.pk, "")
    b = applications.apply(other, offer.pk, "")
    applications.accept(verified_householder, a.pk)
    assert code(lambda: applications.accept(verified_householder, a.pk)) == "invalid_state"
    assert code(lambda: applications.accept(verified_householder, b.pk)) == "invalid_state"
    assert Booking.objects.filter(offer=offer).count() == 1


@pytest.mark.django_db(transaction=True, serialized_rollback=True)
def test_concurrent_requests_stay_consistent(verified_householder, jpeg, verifier, settings):
    """Two devices accepting at once make one booking; simultaneous applications keep the cap."""
    offer = make_offer(verified_householder)
    first, second = j1_jobber(jpeg, verifier), j1_jobber(jpeg, verifier)
    a = applications.apply(first, offer.pk, "")
    b = applications.apply(second, offer.pk, "")
    results = []

    def run(application):
        try:
            applications.accept(verified_householder, application.pk)
            results.append("ok")
        except BookingError as exc:
            results.append(exc.code)
        finally:
            connection.close()

    threads = [threading.Thread(target=run, args=(application,)) for application in (a, b)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert sorted(results) == ["invalid_state", "ok"] or sorted(results) == ["offer_unavailable", "ok"]
    assert Booking.objects.filter(offer=offer).count() == 1

    # Simultaneous applications to different offers must not pass the jobber's cap.
    settings.APPLICATIONS_MAX_OPEN = 1
    busy = j1_jobber(jpeg, verifier)
    others = [make_offer(verified_householder, days=5 + n) for n in range(2)]
    outcomes = []

    def apply_to(target):
        try:
            applications.apply(busy, target.pk, "")
            outcomes.append("ok")
        except BookingError as exc:
            outcomes.append(exc.code)
        finally:
            connection.close()

    workers = [threading.Thread(target=apply_to, args=(target,)) for target in others]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join()
    assert sorted(outcomes) == ["ok", "too_many_applications"]


def test_accept_refused_when_the_applicant_lost_j1(offer, verified_householder, jobber):
    application = applications.apply(jobber, offer.pk, "")
    Guarantor.objects.filter(user=jobber).update(expires_at=timezone.now() - timedelta(days=1))
    assert code(lambda: applications.accept(verified_householder, application.pk)) == "applicant_not_verified"
    assert not Booking.objects.filter(offer=offer).exists()
    offer.refresh_from_db()
    assert offer.status == Offer.Status.PUBLISHED


def test_accept_refused_when_the_offer_is_withdrawn_or_started(offer, verified_householder, jobber):
    application = applications.apply(jobber, offer.pk, "")
    offer_service.withdraw(offer, user=verified_householder)
    assert code(lambda: applications.accept(verified_householder, application.pk)) == "offer_unavailable"
    started = make_offer(verified_householder, days=2)
    other = applications.apply(jobber, started.pk, "")
    Offer.objects.filter(pk=started.pk).update(starts_at=timezone.now() - timedelta(minutes=1))
    assert code(lambda: applications.accept(verified_householder, other.pk)) == "offer_unavailable"


def test_only_the_owner_can_accept(offer, jobber, jpeg, verifier):
    application = applications.apply(jobber, offer.pk, "")
    assert code(lambda: applications.accept(jobber, application.pk)) == "forbidden"
    assert code(lambda: applications.accept(jobber, "not-a-uuid")) == "forbidden"


def test_booked_offer_is_not_visible_to_jobbers(offer, verified_householder, jobber):
    application = applications.apply(jobber, offer.pk, "")
    assert offer in offer_service.visible_to_jobbers()
    applications.accept(verified_householder, application.pk)
    assert offer not in offer_service.visible_to_jobbers()


def test_close_stale_declines_pending_applications_of_dead_offers(verified_householder, jobber):
    live = make_offer(verified_householder, days=2)
    dead = make_offer(verified_householder, days=3)
    started = make_offer(verified_householder, days=4)
    kept = applications.apply(jobber, live.pk, "")
    gone = applications.apply(jobber, dead.pk, "")
    late = applications.apply(jobber, started.pk, "")
    Offer.objects.filter(pk=dead.pk).update(status=Offer.Status.WITHDRAWN)
    Offer.objects.filter(pk=started.pk).update(starts_at=timezone.now() - timedelta(minutes=1))
    assert applications.close_stale() == 2
    for row in (kept, gone, late):
        row.refresh_from_db()
    assert kept.status == Application.Status.PENDING
    assert gone.status == late.status == Application.Status.DECLINED and gone.decided_at


def test_the_sweep_task_runs(verified_householder, jobber):
    from apps.bookings.tasks import close_stale_applications

    assert close_stale_applications() == 0


def test_householder_trust_counts_only_completed_bookings(offer, verified_householder, jobber):
    application = Application.objects.create(offer=offer, jobber=jobber)
    booking_for(offer, application, Booking.Status.ACCEPTED)
    assert applications.householder_trust(verified_householder) == {
        "tier": "H1",
        "jobs_done": 0,
        "rating": None,
    }
    Booking.objects.update(status=Booking.Status.COMPLETED)
    assert applications.householder_trust(verified_householder)["jobs_done"] == 1
