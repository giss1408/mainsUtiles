import pytest
from django.contrib.auth.models import Group
from django.test import Client

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import PaymentMethod
from apps.bookings.services import applications, payments
from apps.bookings.services.applications import BookingError
from tests.helpers import j1_jobber, make_offer

pytestmark = pytest.mark.django_db

METHODS = "/admin/bookings/paymentmethod"


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


@pytest.fixture
def agent(db):
    user = User.objects.create_user(username="cashier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def agent_client(agent):
    client = Client()
    client.force_login(agent)
    return client


def test_no_active_method_means_apply_and_accept_are_refused(verified_householder, jpeg, verifier):
    offer = make_offer(verified_householder)
    jobber = j1_jobber(jpeg, verifier)
    assert not payments.available()
    assert code(lambda: applications.apply(jobber, offer.pk, "")) == "payment_unavailable"
    method = PaymentMethod.objects.create(provider="wave", number="+2250101010101", active=True)
    application = applications.apply(jobber, offer.pk, "")
    method.active = False
    method.save()
    assert code(lambda: applications.accept(verified_householder, application.pk)) == "payment_unavailable"


def test_a_method_without_a_number_does_not_count():
    PaymentMethod.objects.create(provider="wave", number="", active=True)
    assert not payments.available()


def test_switching_the_last_method_off_stops_new_applications_but_not_a_review(
    verified_householder, jpeg, verifier, payment_method
):
    from apps.bookings.models import Application, Booking
    from tests.test_booking_models import booking_for
    from tests.test_payment_models import make_payment

    offer = make_offer(verified_householder)
    booking = booking_for(offer, Application.objects.create(offer=offer, jobber=j1_jobber(jpeg, verifier)))
    payment = make_payment(booking, jpeg)
    payment_method.active = False
    payment_method.save()
    assert not payments.available()
    payment.refresh_from_db()
    assert payment.status == "submitted" and Booking.objects.get(pk=booking.pk).status == "accepted"


def test_instructions_list_only_available_methods_in_order():
    PaymentMethod.objects.create(
        provider="orange_money", number="+2250707070707", account_name="PG", active=True, position=2
    )
    PaymentMethod.objects.create(
        provider="wave", number="+2250101010101", account_name="PG", active=True, position=1
    )
    PaymentMethod.objects.create(provider="mtn_momo", number="+2250505050505", active=False, position=0)
    rows = payments.instructions()
    assert [r["provider"] for r in rows] == ["wave", "orange_money"]
    assert set(rows[0]) == {"id", "provider", "provider_label", "number", "account_name"}
    assert rows[0]["provider_label"] == "Wave"


def test_agent_manages_methods_and_the_number_is_normalised_and_audited(agent_client, agent):
    page = agent_client.post(
        f"{METHODS}/add/",
        {
            "provider": "wave",
            "number": "01 01 01 01 01",
            "account_name": "petitGombo",
            "active": "on",
            "position": 0,
        },
    )
    assert page.status_code == 302
    method = PaymentMethod.objects.get()
    assert method.number == "+2250101010101" and method.active
    assert AdminAction.objects.filter(action="bookings.payment_method.change", actor=agent).exists()
    bad = agent_client.post(
        f"{METHODS}/add/", {"provider": "mtn_momo", "number": "abc", "account_name": "x", "position": 0}
    )
    assert bad.status_code == 200 and PaymentMethod.objects.count() == 1
    assert agent_client.post(f"{METHODS}/{method.pk}/delete/", {"post": "yes"}).status_code == 403


def test_agent_without_the_permission_gets_403(staff_user):
    client = Client()
    client.force_login(staff_user)  # an enrolment agent
    assert client.get(f"{METHODS}/").status_code == 403
