from datetime import timedelta

import pytest
from django.contrib.auth.models import Group, Permission
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment
from apps.bookings.services import bookings, payments
from tests.helpers import paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]

BASE = "/api/v1/staff/payments"


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
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def api(cashier):
    return client_for(cashier)


@pytest.fixture
def paid(verified_householder, jpeg, verifier):
    return paid_booking(verified_householder, jpeg, verifier)


def test_check_queue_lists_submitted_payments_oldest_first_with_the_late_flag_and_no_reference_or_name(
    api, paid, verified_householder, jpeg, verifier
):
    _, first = paid
    Payment.objects.filter(pk=first.pk).update(submitted_at=timezone.now() - timedelta(hours=5))
    _, second = paid_booking(verified_householder, jpeg, verifier, reference="WAVE-777777", days=3, seed=9)
    response = api.get(BASE)
    rows = response.json()["results"]
    assert [r["id"] for r in rows] == [str(first.pk), str(second.pk)]
    assert [r["late"] for r in rows] == [True, False]
    assert (
        rows[0]["action"] == "check" and rows[0]["method_label"] == "Wave" and rows[0]["amount_xof"] == 3000
    )
    raw = response.content.decode()
    assert "WAVE-123456" not in raw and "Jeune" not in raw and verified_householder.phone not in raw
    assert "no-store" in response["Cache-Control"]


def test_refund_queue_needs_the_refund_right_and_check_queue_the_verify_right(paid, verified_householder):
    booking, payment = paid
    verifier_only = client_for(staff_with("verify_payment", username="v"))
    refund_only = client_for(staff_with("make_refund", username="r"))
    nobody = client_for(staff_with(username="n"))
    assert verifier_only.get(BASE).status_code == 200
    assert verifier_only.get(f"{BASE}?file=refund").status_code == 403
    assert refund_only.get(BASE).status_code == 403
    assert refund_only.get(f"{BASE}?file=refund").status_code == 200
    assert nobody.get(BASE).status_code == 403
    payments.confirm_payment(
        payment,
        staff=staff_with("verify_payment", username="v2"),
        amount_matches=True,
        reference_matches=True,
    )
    bookings.cancel(verified_householder, booking.pk)
    rows = refund_only.get(f"{BASE}?file=refund").json()["results"]
    assert [(r["id"], r["action"]) for r in rows] == [(str(payment.pk), "refund")]
    assert refund_only.get(f"{BASE}/{payment.pk}").status_code == 200
    assert verifier_only.get(f"{BASE}/{payment.pk}").status_code == 404


def test_detail_shows_the_reference_and_audits_the_view(api, cashier, paid):
    _, payment = paid
    body = api.get(f"{BASE}/{payment.pk}").json()
    assert body["reference"] == "WAVE-123456" and body["method_number"] == "+2250101010101"
    assert body["fee_xof"] == 0 and body["seen_before"] is False and body["status"] == "submitted"
    assert AdminAction.objects.filter(action="booking.payment.view", actor=cashier).exists()
    assert "no-store" in api.get(f"{BASE}/{payment.pk}")["Cache-Control"]


def test_a_decided_or_unqueued_payment_is_404(api, cashier, paid):
    _, payment = paid
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    assert api.get(f"{BASE}/{payment.pk}").status_code == 404
    assert api.get(f"{BASE}/{payment.pk}/proof").status_code == 404
    assert api.get(f"{BASE}/00000000-0000-0000-0000-000000000000").status_code == 404


def test_proof_is_no_store_and_audited(api, cashier, paid, jpeg):
    _, payment = paid
    response = api.get(f"{BASE}/{payment.pk}/proof")
    assert response.status_code == 200 and response["Content-Type"] == "image/jpeg"
    assert "no-store" in response["Cache-Control"] and response.content == jpeg(7)
    assert AdminAction.objects.filter(action="booking.payment.view_proof", actor=cashier).exists()


def test_confirm_and_refuse_and_refund_through_the_api(api, paid, verified_householder, jpeg, verifier):
    booking, payment = paid
    confirmed = api.post(
        f"{BASE}/{payment.pk}/confirm", {"amount_matches": True, "reference_matches": True}, format="json"
    )
    assert confirmed.status_code == 200 and confirmed.json()["id"] == str(payment.pk)
    assert Booking.objects.get(pk=booking.pk).status == "confirmed"
    other, second = paid_booking(
        verified_householder, jpeg, verifier, reference="WAVE-888888", days=3, seed=9
    )
    refused = api.post(f"{BASE}/{second.pk}/refuse", {"reason": "Montant faux"}, format="json")
    assert refused.status_code == 200 and Payment.objects.get(pk=second.pk).reason == "Montant faux"
    bookings.cancel(verified_householder, booking.pk)
    refunded = api.post(f"{BASE}/{payment.pk}/refund", {"reference": "RB-2001"}, format="json")
    assert refunded.status_code == 200 and Payment.objects.get(pk=payment.pk).status == "refunded"
    assert other.pk


def test_both_checks_are_required(api, paid):
    _, payment = paid
    response = api.post(f"{BASE}/{payment.pk}/confirm", {"amount_matches": True}, format="json")
    assert response.status_code == 400 and response.json()["error"] == "checks_required"
    assert Payment.objects.get(pk=payment.pk).status == "submitted"


def test_second_decision_is_409_with_the_message(api, paid):
    _, payment = paid
    api.post(f"{BASE}/{payment.pk}/refuse", {"reason": "non"}, format="json")
    again = api.post(f"{BASE}/{payment.pk}/refuse", {"reason": "non"}, format="json")
    assert again.status_code == 409 and again.json()["error"] == "invalid_state"


def test_a_jobber_or_householder_token_gets_403(paid, verified_householder):
    booking, payment = paid
    for user in (verified_householder, booking.jobber):
        client = client_for(user)
        assert client.get(BASE).status_code == 403
        assert client.post(f"{BASE}/{payment.pk}/confirm", {}, format="json").status_code == 403
