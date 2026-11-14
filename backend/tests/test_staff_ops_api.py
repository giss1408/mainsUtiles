"""Stage 4: the staff app's messages, payouts, disputes and alerts."""

from datetime import timedelta

import pytest
from django.contrib.auth.models import Group, Permission
from django.test import Client
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Message, Payment, Payout, Report
from apps.bookings.services import bookings, jobs, reports
from tests.helpers import accepted_booking, confirmed_booking, paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]

BASE = "/api/v1/staff"
TEXT = "Le salon reste sale"


def staff_with(*codenames, username="agent"):
    user = User.objects.create_user(username=username, password="pw", role="staff", is_staff=True)
    user.user_permissions.add(
        *Permission.objects.filter(content_type__app_label="bookings", codename__in=codenames)
    )
    return user


def client_for(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


@pytest.fixture
def agent(db):
    user = User.objects.create_user(username="cashier2", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def api(agent):
    return client_for(agent)


@pytest.fixture
def accepted(verified_householder, jpeg, verifier):
    return accepted_booking(verified_householder, jpeg, verifier)


@pytest.fixture
def working(verified_householder, jpeg, verifier):
    booking = confirmed_booking(verified_householder, jpeg, verifier)
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    return jobs.check_in(booking.jobber, booking.pk, lat=None, lng=None)


@pytest.fixture
def payout(working):
    jobs.check_out(working.jobber, working.pk)
    return jobs.confirm_done(working.householder, working.pk).payout


@pytest.fixture
def dispute(working):
    return reports.report_problem(working.householder, working.pk, text=TEXT, dispute=True)


# ---- Messages ----


def test_queue_lists_pending_without_text_or_number(api, accepted):
    response = api.get(f"{BASE}/messages")
    rows = response.json()["results"]
    assert response["Cache-Control"] == "no-store"
    assert [r["kind"] for r in rows] == ["accepted"]
    assert set(rows[0]) == {"id", "kind", "kind_label", "recipient_role", "urgent", "late", "created_at"}
    assert rows[0]["kind_label"] == "Candidature acceptée" and rows[0]["recipient_role"] == "jobber"
    assert accepted.jobber.phone not in response.content.decode()


def test_detail_shows_the_text_and_audits(api, agent, accepted):
    message = Message.objects.get(kind="accepted")
    response = api.get(f"{BASE}/messages/{message.pk}")
    body = response.json()
    assert response["Cache-Control"] == "no-store"
    assert body["text"].startswith("petitGombo : tu as été accepté(e)") and body["category_name"] == "Ménage"
    assert accepted.jobber.phone not in response.content.decode()
    assert AdminAction.objects.filter(action="booking.message.view", actor=agent).count() == 1


def test_send_returns_the_link_once(api, accepted):
    message = Message.objects.get(kind="accepted")
    response = api.post(f"{BASE}/messages/{message.pk}/send")
    assert response.status_code == 200 and response["Cache-Control"] == "no-store"
    assert response.json()["whatsapp_url"].startswith(f"https://wa.me/{accepted.jobber.phone.lstrip('+')}")
    assert api.post(f"{BASE}/messages/{message.pk}/send").status_code == 409
    assert api.get(f"{BASE}/messages/{message.pk}").status_code == 404
    assert api.get(f"{BASE}/messages").json()["results"] == []


def test_a_stale_message_answers_409_and_leaves_the_queue(api, accepted):
    message = Message.objects.get(kind="accepted")
    bookings.cancel(accepted.householder, accepted.pk)
    response = api.post(f"{BASE}/messages/{message.pk}/send")
    assert response.status_code == 409 and response.json()["error"] == "message_stale"
    assert "whatsapp_url" not in response.json()
    kinds = [r["kind"] for r in api.get(f"{BASE}/messages").json()["results"]]
    assert kinds == ["cancelled"]


def test_messages_need_the_right(accepted):
    message = Message.objects.get(kind="accepted")
    for user in (staff_with("make_payout"), accepted.jobber):
        client = client_for(user)
        assert client.get(f"{BASE}/messages").status_code == 403
        assert client.get(f"{BASE}/messages/{message.pk}").status_code == 403
        assert client.post(f"{BASE}/messages/{message.pk}/send").status_code == 403
    assert APIClient().get(f"{BASE}/messages").status_code in (401, 403)
    assert Message.objects.get(pk=message.pk).status == "pending"
    assert (
        client_for(staff_with("send_message", username="sender")).get(f"{BASE}/messages").status_code == 200
    )


# ---- Payouts ----


def test_payout_queue_detail_and_pay(api, agent, payout):
    rows = api.get(f"{BASE}/payouts").json()["results"]
    assert set(rows[0]) == {"id", "category_name", "amount_xof", "due_at", "late"}
    assert rows[0]["id"] == str(payout.pk) and rows[0]["amount_xof"] == 3000 and rows[0]["late"] is False
    bad = api.post(f"{BASE}/payouts/{payout.pk}/pay", {"reference": "x"}, format="json")
    assert bad.status_code == 400 and bad.json()["error"] == "reference_invalid"
    done = api.post(f"{BASE}/payouts/{payout.pk}/pay", {"reference": "MOMO-998877"}, format="json")
    assert done.status_code == 200 and done["Cache-Control"] == "no-store"
    assert "MOMO-998877" not in done.content.decode()
    payout.refresh_from_db()
    assert payout.status == Payout.Status.PAID and payout.paid_by == agent
    assert api.get(f"{BASE}/payouts").json()["results"] == []
    assert (
        api.post(f"{BASE}/payouts/{payout.pk}/pay", {"reference": "MOMO-112233"}, format="json").status_code
        == 409
    )
    assert api.get(f"{BASE}/payouts/{payout.pk}").status_code == 404
    assert Message.objects.filter(kind="paid").count() == 1


def test_payout_detail_audits_and_shows_the_phone_only_there(api, agent, payout, settings):
    listing = api.get(f"{BASE}/payouts")
    assert payout.booking.jobber.phone not in listing.content.decode()
    detail = api.get(f"{BASE}/payouts/{payout.pk}")
    assert detail["Cache-Control"] == "no-store"
    assert detail.json()["jobber_phone"] == payout.booking.jobber.phone and detail.json()["payable"] is True
    assert AdminAction.objects.filter(action="booking.payout.view", actor=agent).count() == 1
    Payout.objects.filter(pk=payout.pk).update(
        due_at=timezone.now() - timedelta(hours=settings.PAYOUT_LATE_HOURS, minutes=1)
    )
    assert api.get(f"{BASE}/payouts").json()["results"][0]["late"] is True


def test_a_refunded_booking_cannot_be_paid_from_the_app(api, payout):
    Payment.objects.filter(booking=payout.booking).update(status=Payment.Status.REFUND_DUE)
    assert api.get(f"{BASE}/payouts/{payout.pk}").json()["payable"] is False
    response = api.post(f"{BASE}/payouts/{payout.pk}/pay", {"reference": "MOMO-998877"}, format="json")
    assert response.status_code == 409
    payout.refresh_from_db()
    assert payout.status == Payout.Status.DUE


# ---- Disputes ----


@pytest.mark.parametrize(
    "body,status,paid",
    [
        ({"outcome": "release", "note": "Photos"}, "completed", 3000),
        ({"outcome": "refund", "note": "Parti tôt"}, "cancelled", None),
        ({"outcome": "split", "note": "Moitié", "jobber_xof": 1200}, "completed", 1200),
    ],
)
def test_dispute_queue_detail_and_each_resolution(api, agent, dispute, working, body, status, paid):
    listing = api.get(f"{BASE}/disputes")
    rows = listing.json()["results"]
    assert set(rows[0]) == {"id", "category_name", "created_at", "late"} and rows[0]["id"] == str(dispute.pk)
    assert TEXT not in listing.content.decode()
    detail = api.get(f"{BASE}/disputes/{dispute.pk}")
    data = detail.json()
    assert detail["Cache-Control"] == "no-store"
    assert data["text"] == TEXT and data["author_side"] == "householder" and data["jobber_name"] == "Jeune"
    assert data["pay_xof"] == 3000 and data["checked_in_at"] and data["far"] is False
    assert data["payment_state"] == "Confirmé"
    raw = detail.content.decode()
    assert working.jobber.phone not in raw and working.householder.phone not in raw and "Jobber" not in raw
    assert AdminAction.objects.filter(action="booking.report.view", actor=agent).count() == 1
    done = api.post(f"{BASE}/disputes/{dispute.pk}/resolve", body, format="json")
    assert done.status_code == 200
    working.refresh_from_db()
    assert working.status == status
    found = Payout.objects.filter(booking=working).first()
    assert (found.amount_xof if found else None) == paid
    assert api.get(f"{BASE}/disputes").json()["results"] == []
    assert api.post(f"{BASE}/disputes/{dispute.pk}/resolve", body, format="json").status_code == 409
    assert api.get(f"{BASE}/disputes/{dispute.pk}").status_code == 404


def test_bad_split_and_missing_note(api, dispute):
    url = f"{BASE}/disputes/{dispute.pk}/resolve"
    for amount in (None, 0, 3000):
        response = api.post(url, {"outcome": "split", "note": "x", "jobber_xof": amount}, format="json")
        assert response.status_code == 400 and response.json()["error"] == "split_invalid"
    missing = api.post(url, {"outcome": "release", "note": " "}, format="json")
    assert missing.status_code == 400 and missing.json()["error"] == "reason_required"
    unknown = api.post(url, {"outcome": "burn", "note": "x"}, format="json")
    assert unknown.status_code == 400 and unknown.json()["error"] == "outcome_invalid"
    dispute.refresh_from_db()
    assert dispute.status == Report.Status.OPEN


def test_a_concern_is_not_in_the_app(api, working):
    concern = reports.report_problem(working.jobber, working.pk, text=TEXT, dispute=False)
    assert api.get(f"{BASE}/disputes").json()["results"] == []
    assert api.get(f"{BASE}/disputes/{concern.pk}").status_code == 404
    response = api.post(
        f"{BASE}/disputes/{concern.pk}/resolve", {"outcome": "release", "note": "x"}, format="json"
    )
    assert response.status_code == 409


def test_rights_are_separate(payout, verified_householder, jpeg, verifier):
    payer = client_for(staff_with("make_payout", username="payer"))
    judge = client_for(staff_with("resolve_dispute", username="judge"))
    assert payer.get(f"{BASE}/payouts").status_code == 200
    assert payer.get(f"{BASE}/disputes").status_code == 403
    assert judge.get(f"{BASE}/disputes").status_code == 200
    assert judge.get(f"{BASE}/payouts").status_code == 403
    assert judge.get(f"{BASE}/payouts/{payout.pk}").status_code == 403
    assert (
        judge.post(f"{BASE}/payouts/{payout.pk}/pay", {"reference": "MOMO-998877"}, format="json").status_code
        == 403
    )
    assert not AdminAction.objects.filter(action="booking.payout.view").exists()


# ---- Alerts and console ----


def test_counts_follow_the_queues_and_the_late_limits(api, verified_householder, jpeg, verifier, settings):
    empty = api.get(f"{BASE}/alerts")
    assert empty["Cache-Control"] == "no-store"
    assert set(empty.json()) == {
        "payments_waiting", "payments_late", "refunds_waiting", "payouts_waiting", "payouts_late",
        "disputes_open", "disputes_late", "far_checkins", "messages_waiting", "messages_late",
    }  # fmt: skip
    assert set(empty.json().values()) == {0}
    _, payment = paid_booking(verified_householder, jpeg, verifier)
    Payment.objects.filter(pk=payment.pk).update(submitted_at=timezone.now() - timedelta(hours=5))
    counts = api.get(f"{BASE}/alerts").json()
    assert counts["payments_waiting"] == 1 and counts["payments_late"] == 1
    assert counts["messages_waiting"] == 1 and counts["messages_late"] == 0  # accepted
    Message.objects.update(created_at=timezone.now() - timedelta(minutes=settings.MESSAGE_LATE_MINUTES + 1))
    assert api.get(f"{BASE}/alerts").json()["messages_late"] == 1


def test_payout_dispute_and_far_check_in_counts(api, working, settings):
    Booking.objects.filter(pk=working.pk).update(checkin_distance_m=settings.CHECKIN_FLAG_METERS + 1)
    assert api.get(f"{BASE}/alerts").json()["far_checkins"] == 1
    report = reports.report_problem(working.householder, working.pk, text=TEXT, dispute=True)
    counts = api.get(f"{BASE}/alerts").json()
    assert counts["disputes_open"] == 1 and counts["disputes_late"] == 0 and counts["far_checkins"] == 0
    Report.objects.filter(pk=report.pk).update(
        created_at=timezone.now() - timedelta(hours=settings.DISPUTE_LATE_HOURS, minutes=1)
    )
    assert api.get(f"{BASE}/alerts").json()["disputes_late"] == 1
    reports.resolve_dispute(report, staff=User.objects.get(username="cashier2"), outcome="release", note="x")
    counts = api.get(f"{BASE}/alerts").json()
    assert counts["disputes_open"] == 0 and counts["payouts_waiting"] == 1 and counts["payouts_late"] == 0


def test_counts_show_only_what_the_user_may_work(accepted):
    sender = client_for(staff_with("send_message", username="sender"))
    assert sender.get(f"{BASE}/alerts").json() == {"messages_waiting": 1, "messages_late": 0}
    assert client_for(staff_with(username="bare")).get(f"{BASE}/alerts").json() == {}
    assert client_for(accepted.jobber).get(f"{BASE}/alerts").status_code == 403


def test_message_console_is_read_only_and_shows_no_number(agent, accepted):
    console = Client()
    console.force_login(agent)
    message = Message.objects.get(kind="accepted")
    listing = console.get("/admin/bookings/message/")
    page = listing.content.decode()
    assert listing.status_code == 200 and "Candidature acceptée" in page and "Jobber" in page
    assert accepted.jobber.phone not in page
    detail = console.get(f"/admin/bookings/message/{message.pk}/change/")
    assert detail.status_code == 200 and accepted.jobber.phone not in detail.content.decode()
    assert (
        console.post(f"/admin/bookings/message/{message.pk}/change/", {"status": "sent"}).status_code == 403
    )
    assert console.get("/admin/bookings/message/add/").status_code == 403


def test_the_schema_validates():
    from django.core.management import call_command

    call_command("spectacular", "--validate", "--file", "/dev/null")
