from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Payment
from apps.bookings.services import bookings, payments
from tests.helpers import paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]

PAY = "/admin/bookings/payment"


@pytest.fixture
def cashier(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def client(cashier):
    c = Client()
    c.force_login(cashier)
    return c


@pytest.fixture
def paid(verified_householder, jpeg, verifier):
    return paid_booking(verified_householder, jpeg, verifier)


def test_agent_sees_the_queue_oldest_first_with_the_late_marker(
    client, paid, verified_householder, jpeg, verifier
):
    booking, payment = paid
    Payment.objects.filter(pk=payment.pk).update(submitted_at=timezone.now() - timedelta(hours=5))
    _, newer = paid_booking(verified_householder, jpeg, verifier, reference="WAVE-777777", days=3, seed=9)
    page = client.get(f"{PAY}/").content.decode()
    assert page.index(str(payment.pk)) < page.index(str(newer.pk))
    assert page.count("En retard") == 1 and "Ménage" in page


def test_list_page_shows_no_reference_or_name(client, paid, verified_householder):
    page = client.get(f"{PAY}/?file=all").content.decode()
    assert "WAVE-123456" not in page and "Jeune" not in page and verified_householder.phone not in page


def test_review_page_shows_the_proof_the_amount_and_audits_the_view(client, cashier, paid):
    _, payment = paid
    response = client.get(f"{PAY}/{payment.pk}/change/")
    page = response.content.decode()
    assert "WAVE-123456" in page and "3000 FCFA" in page and "Wave" in page
    assert f"{PAY}/{payment.pk}/proof/" in page and "Le montant correspond" in page
    assert "no-store" in response["Cache-Control"]
    assert AdminAction.objects.filter(action="booking.payment.view", actor=cashier).exists()


def test_the_proof_image_is_no_store_and_audited(client, cashier, paid, jpeg):
    _, payment = paid
    response = client.get(f"{PAY}/{payment.pk}/proof/")
    assert response.status_code == 200 and response["Content-Type"] == "image/jpeg"
    assert "no-store" in response["Cache-Control"] and response.content == jpeg(7)
    assert AdminAction.objects.filter(action="booking.payment.view_proof", actor=cashier).exists()


def test_an_image_seen_before_is_warned_about(client, paid, verified_householder, jpeg, verifier):
    _, second = paid_booking(verified_householder, jpeg, verifier, reference="WAVE-777777", days=3, seed=7)
    assert "déjà été envoyée" in client.get(f"{PAY}/{second.pk}/change/").content.decode()


def test_confirm_and_refuse_through_the_console(client, paid, verified_householder, jpeg, verifier):
    booking, payment = paid
    refused = client.post(f"{PAY}/{payment.pk}/confirm/", {"amount_matches": "on"}, follow=True)
    assert "Cochez les deux vérifications" in refused.content.decode()
    client.post(f"{PAY}/{payment.pk}/confirm/", {"amount_matches": "on", "reference_matches": "on"})
    payment.refresh_from_db()
    booking.refresh_from_db()
    assert payment.status == Payment.Status.CONFIRMED and booking.status == Booking.Status.CONFIRMED
    other, second = paid_booking(
        verified_householder, jpeg, verifier, reference="WAVE-888888", days=3, seed=9
    )
    client.post(f"{PAY}/{second.pk}/refuse/", {"reason": "Montant faux"})
    second.refresh_from_db()
    other.refresh_from_db()
    assert second.status == Payment.Status.REFUSED and other.status == Booking.Status.ACCEPTED
    again = client.post(f"{PAY}/{second.pk}/refuse/", {"reason": "x"}, follow=True)
    assert "déjà été traité" in again.content.decode()


def test_refund_queue_and_recording(client, cashier, paid, verified_householder):
    booking, payment = paid
    payments.confirm_payment(payment, staff=cashier, amount_matches=True, reference_matches=True)
    bookings.cancel(verified_householder, booking.pk)
    assert str(payment.pk) in client.get(f"{PAY}/?file=refund").content.decode()
    assert str(payment.pk) not in client.get(f"{PAY}/").content.decode()
    client.post(f"{PAY}/{payment.pk}/refund/", {"reference": "RB-2001"})
    payment.refresh_from_db()
    assert payment.status == Payment.Status.REFUNDED


def test_agent_without_the_permission_gets_403(paid, staff_user):
    _, payment = paid
    other = Client()
    other.force_login(staff_user)  # an enrolment agent
    assert other.get(f"{PAY}/").status_code == 403
    assert (
        other.post(
            f"{PAY}/{payment.pk}/confirm/", {"amount_matches": "on", "reference_matches": "on"}
        ).status_code
        == 403
    )
    assert other.get(f"{PAY}/{payment.pk}/proof/").status_code == 403


def test_the_agent_cannot_edit_or_delete_a_payment(client, paid):
    _, payment = paid
    assert client.post(f"{PAY}/{payment.pk}/delete/", {"post": "yes"}).status_code == 403
    assert client.get(f"{PAY}/add/").status_code == 403
