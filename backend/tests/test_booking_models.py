import pytest
from django.db import IntegrityError, transaction

from apps.bookings.models import Application, Booking
from apps.listings.models import Offer
from apps.listings.services import screening
from tests.helpers import j1_jobber, make_offer

pytestmark = pytest.mark.django_db


@pytest.fixture
def offer(verified_householder):
    return make_offer(verified_householder)


@pytest.fixture
def jobber(jpeg, verifier):
    return j1_jobber(jpeg, verifier)


def booking_for(offer, application, status=Booking.Status.ACCEPTED):
    return Booking.objects.create(
        offer=offer,
        application=application,
        householder=offer.author,
        jobber=application.jobber,
        category_name=offer.category_name,
        duties=offer.duties,
        starts_at=offer.starts_at,
        duration_minutes=offer.duration_minutes,
        pay_xof=offer.pay_xof,
        commune=offer.commune,
        quartier=offer.quartier,
        status=status,
    )


def test_a_jobber_has_one_live_application_per_offer(offer, jobber):
    Application.objects.create(offer=offer, jobber=jobber)
    with pytest.raises(IntegrityError), transaction.atomic():
        Application.objects.create(offer=offer, jobber=jobber)


def test_a_withdrawn_application_does_not_block_a_new_one(offer, jobber):
    first = Application.objects.create(offer=offer, jobber=jobber)
    first.status = Application.Status.WITHDRAWN
    first.save()
    Application.objects.create(offer=offer, jobber=jobber)


def test_an_offer_has_one_live_booking(offer, jobber):
    first = Application.objects.create(offer=offer, jobber=jobber)
    booking_for(offer, first)
    second = Application.objects.create(offer=offer, jobber=jobber, status=Application.Status.WITHDRAWN)
    with pytest.raises(IntegrityError), transaction.atomic():
        booking_for(offer, second)


def test_a_cancelled_booking_frees_the_offer(offer, jobber):
    first = Application.objects.create(offer=offer, jobber=jobber, status=Application.Status.WITHDRAWN)
    booking_for(offer, first, Booking.Status.CANCELLED)
    second = Application.objects.create(offer=offer, jobber=jobber)
    booking_for(offer, second)
    assert Booking.objects.filter(offer=offer).count() == 2


def test_booked_is_not_an_open_status():
    assert Offer.Status.BOOKED.value == "booked"
    assert Offer.Status.BOOKED.value not in Offer.OPEN_STATUSES


@pytest.mark.parametrize(
    "text",
    ["07 08 09 10 11", "0708.09.10.11", "+225 0708091011", "a@b.ci", "Ecris-moi sur WhatsApp", "whatsapp"],
)
def test_contact_in_catches_numbers_emails_and_off_platform_terms(text):
    assert screening.contact_in(text)


def test_contact_in_lets_an_ordinary_message_through():
    assert not screening.contact_in("Je suis disponible le matin, j'ai déjà fait du ménage.")
