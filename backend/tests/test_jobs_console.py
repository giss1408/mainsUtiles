from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment, Payout, Report
from apps.bookings.services import jobs, payouts, reports
from tests.helpers import confirmed_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]

PAYOUT = "/admin/bookings/payout"
REPORT = "/admin/bookings/report"
TEXT = "Le salon reste sale"


@pytest.fixture
def agent(db):
    user = User.objects.create_user(username="payer", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def client(agent):
    c = Client()
    c.force_login(agent)
    return c


@pytest.fixture
def working(verified_householder, jpeg, verifier):
    booking = confirmed_booking(verified_householder, jpeg, verifier)
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    return jobs.check_in(booking.jobber, booking.pk, lat=None, lng=None)


@pytest.fixture
def payout(working, verified_householder):
    jobs.check_out(working.jobber, working.pk)
    return jobs.confirm_done(verified_householder, working.pk).payout


@pytest.fixture
def dispute(working, verified_householder):
    return reports.report_problem(verified_householder, working.pk, text=TEXT, dispute=True)


def test_payout_queue_page_and_recording(client, agent, payout):
    assert str(payout.pk) in client.get(f"{PAYOUT}/").content.decode()
    bad = client.post(f"{PAYOUT}/{payout.pk}/pay/", {"reference": "x"}, follow=True)
    assert "Indiquez la référence" in bad.content.decode()
    done = client.post(f"{PAYOUT}/{payout.pk}/pay/", {"reference": "MOMO-998877"}, follow=True)
    assert "Paiement au jobber enregistré." in done.content.decode()
    payout.refresh_from_db()
    assert payout.status == Payout.Status.PAID and payout.paid_by == agent
    assert str(payout.pk) not in client.get(f"{PAYOUT}/").content.decode()
    assert str(payout.pk) in client.get(f"{PAYOUT}/?file=paid").content.decode()
    again = client.post(f"{PAYOUT}/{payout.pk}/pay/", {"reference": "MOMO-112233"}, follow=True)
    assert "ne peut pas être versé" in again.content.decode()
    assert client.get(f"{PAYOUT}/{payout.pk}/pay/").status_code == 405


def test_payout_page_shows_the_phone_audits_and_is_no_store(client, agent, payout):
    response = client.get(f"{PAYOUT}/{payout.pk}/change/")
    page = response.content.decode()
    assert payout.booking.jobber.phone in page and f"{payout.amount_xof} FCFA" in page and "Ménage" in page
    assert "Enregistrer le versement" in page
    assert "no-store" in response["Cache-Control"]
    assert AdminAction.objects.filter(action="booking.payout.view", actor=agent).count() == 1
    Payment.objects.filter(booking=payout.booking).update(status=Payment.Status.REFUND_DUE)
    page = client.get(f"{PAYOUT}/{payout.pk}/change/").content.decode()
    assert "Ne versez rien" in page and "Enregistrer le versement" not in page


def test_lists_show_no_phone_text_or_reference(client, agent, payout, working):
    reports.report_problem(working.jobber, working.pk, text=TEXT, dispute=False)
    payouts.record_payout(payout, staff=agent, reference="MOMO-998877")
    for url in (f"{PAYOUT}/?file=all", f"{REPORT}/?file=all", f"{REPORT}/?file=concerns"):
        page = client.get(url).content.decode()
        assert working.jobber.phone not in page and working.householder.phone not in page
        assert TEXT not in page and "salon" not in page and "MOMO-998877" not in page


@pytest.mark.parametrize(
    "form,status,paid",
    [
        ({"outcome": "release", "note": "Photos"}, "completed", 3000),
        ({"outcome": "refund", "note": "Parti tôt"}, "cancelled", None),
        ({"outcome": "split", "note": "Moitié", "jobber_xof": "1200"}, "completed", 1200),
    ],
)
def test_dispute_page_and_each_resolution(client, agent, dispute, working, form, status, paid):
    assert str(dispute.pk) in client.get(f"{REPORT}/").content.decode()
    response = client.get(f"{REPORT}/{dispute.pk}/change/")
    page = response.content.decode()
    assert TEXT in page and "Jeune" in page and "Trancher le litige" in page and "Distance" in page
    assert working.jobber.phone not in page and working.householder.phone not in page
    assert "no-store" in response["Cache-Control"]
    assert AdminAction.objects.filter(action="booking.report.view", actor=agent).exists()
    missing = client.post(f"{REPORT}/{dispute.pk}/resolve/", {**form, "note": ""}, follow=True)
    assert "Le motif est obligatoire." in missing.content.decode()
    done = client.post(f"{REPORT}/{dispute.pk}/resolve/", form, follow=True)
    assert "Litige tranché." in done.content.decode() and "Trancher le litige" not in done.content.decode()
    working.refresh_from_db()
    assert working.status == status
    found = Payout.objects.filter(booking=working).first()
    assert (found.amount_xof if found else None) == paid
    assert str(dispute.pk) not in client.get(f"{REPORT}/").content.decode()
    again = client.post(f"{REPORT}/{dispute.pk}/resolve/", form, follow=True)
    assert "déjà été tranché" in again.content.decode()


def test_a_bad_split_is_explained(client, dispute):
    for amount in ("", "abc", "0", "3000"):
        page = client.post(
            f"{REPORT}/{dispute.pk}/resolve/",
            {"outcome": "split", "note": "x", "jobber_xof": amount},
            follow=True,
        ).content.decode()
        assert "Le montant du jobber" in page
    dispute.refresh_from_db()
    assert dispute.status == Report.Status.OPEN


def test_concerns_are_listed_but_have_no_resolution_form(client, working):
    concern = reports.report_problem(working.jobber, working.pk, text=TEXT, dispute=False)
    assert str(concern.pk) not in client.get(f"{REPORT}/").content.decode()
    assert str(concern.pk) in client.get(f"{REPORT}/?file=concerns").content.decode()
    page = client.get(f"{REPORT}/{concern.pk}/change/").content.decode()
    assert TEXT in page and "Trancher le litige" not in page
    client.post(f"{REPORT}/{concern.pk}/resolve/", {"outcome": "release", "note": "x"})
    concern.refresh_from_db()
    assert concern.status == Report.Status.OPEN


def test_without_the_permission_gets_403(payout, working, staff_user):
    dispute = reports.report_problem(working.jobber, working.pk, text=TEXT, dispute=False)
    c = Client()
    c.force_login(staff_user)
    for url in (
        f"{PAYOUT}/",
        f"{PAYOUT}/{payout.pk}/change/",
        f"{REPORT}/",
        f"{REPORT}/{dispute.pk}/change/",
    ):
        assert c.get(url).status_code == 403
    assert c.post(f"{PAYOUT}/{payout.pk}/pay/", {"reference": "MOMO-998877"}).status_code == 403
    assert c.post(f"{REPORT}/{dispute.pk}/resolve/", {"outcome": "release", "note": "x"}).status_code == 403
    payout.refresh_from_db()
    assert payout.status == Payout.Status.DUE
