import pytest
from django.test import Client

from apps.bookings.services import applications
from tests.helpers import j1_jobber, make_offer

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]


@pytest.fixture
def staff_client(db):
    from apps.accounts.models import User

    user = User.objects.create_superuser(username="boss", password="pw")
    client = Client()
    client.force_login(user)
    return client


@pytest.fixture
def booked(verified_householder, jpeg, verifier):
    offer = make_offer(verified_householder)
    jobber = j1_jobber(jpeg, verifier)
    application = applications.apply(jobber, offer.pk, "Un mot secret pour le ménage")
    return applications.accept(verified_householder, application.pk), jobber


def test_staff_can_list_applications_and_bookings_but_not_edit(staff_client, booked):
    booking, jobber = booked
    for name in ("application", "booking"):
        page = staff_client.get(f"/admin/bookings/{name}/")
        assert page.status_code == 200 and jobber.phone in page.content.decode()
        assert staff_client.get(f"/admin/bookings/{name}/add/").status_code == 403
    detail = staff_client.get(f"/admin/bookings/booking/{booking.pk}/change/")
    assert detail.status_code == 200
    assert staff_client.post(f"/admin/bookings/booking/{booking.pk}/delete/").status_code == 403
    assert (
        staff_client.post(
            f"/admin/bookings/booking/{booking.pk}/change/", {"status": "cancelled"}
        ).status_code
        == 403
    )


def test_the_list_pages_show_no_message_text(staff_client, booked):
    assert "secret" not in staff_client.get("/admin/bookings/application/").content.decode()
    application = booked[0].application
    detail = staff_client.get(f"/admin/bookings/application/{application.pk}/change/")
    assert "secret" in detail.content.decode()
