import pytest

from apps.audit.models import AdminAction
from apps.verification.models import Status
from apps.verification.services import review
from apps.verification.services.tiers import householder_tier
from tests.test_verification_review import address_values, identity_values
from tests.test_verification_submissions import send_address, send_identity, send_location

pytestmark = pytest.mark.django_db

IDENTITIES = "/admin/verification/identityverification"
ADDRESSES = "/admin/verification/addressproof"

IDENTITY_FORM = {
    "full_name": "Kouassi Aya",
    "date_of_birth": "1990-05-17",
    "document_number": "CI 001-234 567",
    "document_expires_on": "2030-01-01",
}
ADDRESS_FORM = {
    "holder_name": "Kouassi Aya",
    "reference_number": "CIE-889900",
    "issued_on": "",  # set per test: must be recent
    "name_matches": "on",
    "address_consistent": "on",
}


def recent():
    from django.utils import timezone

    return (timezone.localdate()).isoformat()


def test_verification_agent_sees_both_queues_with_only_open_records(
    verifier_client, verifier, householder, jpeg
):
    record = send_identity(householder, jpeg)
    send_address(householder, jpeg)
    listing = verifier_client.get(f"{IDENTITIES}/").content.decode()
    assert "+2250505050505" in listing and "Vérifications" in listing
    assert verifier_client.get(f"{ADDRESSES}/").status_code == 200

    review.refuse_identity(record, staff=verifier, reason="Photo floue")
    assert "+2250505050505" not in verifier_client.get(f"{IDENTITIES}/").content.decode()
    assert "+2250505050505" in verifier_client.get(f"{IDENTITIES}/?etat=all").content.decode()


def test_enrolment_agent_gets_403_on_queues_pages_and_photos(agent_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    proof = send_address(householder, jpeg)
    for path in (
        f"{IDENTITIES}/",
        f"{IDENTITIES}/{record.pk}/change/",
        f"{IDENTITIES}/{record.pk}/photo/{record.front.pk}/",
        f"{ADDRESSES}/",
        f"{ADDRESSES}/{proof.pk}/change/",
        f"{ADDRESSES}/{proof.pk}/photo/{proof.photo.pk}/",
    ):
        assert agent_client.get(path).status_code == 403, path
    assert agent_client.post(f"{IDENTITIES}/{record.pk}/confirm/", IDENTITY_FORM).status_code == 403
    assert agent_client.post(f"{ADDRESSES}/{proof.pk}/refuse/", {"reason": "x"}).status_code == 403
    record.refresh_from_db()
    assert record.status == Status.SUBMITTED
    assert not AdminAction.objects.filter(action__startswith="verification").exists()


def test_opening_identity_page_marks_in_review_and_shows_three_photo_links(
    verifier_client, householder, jpeg
):
    record = send_identity(householder, jpeg)
    r = verifier_client.get(f"{IDENTITIES}/{record.pk}/change/")
    html = r.content.decode()
    assert r.status_code == 200 and "no-store" in r["Cache-Control"]
    for photo in (record.front, record.back, record.selfie):
        assert f"{IDENTITIES}/{record.pk}/photo/{photo.pk}/" in html
    for label in (
        "Nom complet",
        "Date de naissance",
        "Numéro du document",
        "Date d'expiration",
        "Confirmer",
        "Refuser",
    ):
        assert label in html
    assert ".bin" not in html
    record.refresh_from_db()
    assert record.status == Status.IN_REVIEW


def test_reused_photo_flag_is_shown_in_french(verifier_client, householder, jpeg, enrol_device):
    send_identity(householder, jpeg)
    other = enrol_device(phone="0101010102", role="householder").device.user
    record = send_identity(other, jpeg)
    html = verifier_client.get(f"{IDENTITIES}/{record.pk}/change/").content.decode()
    assert "Cette photo a déjà été envoyée par un autre compte." in html


def test_photo_view_returns_the_jpeg_with_no_store_and_audits(verifier_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    proof = send_address(householder, jpeg)
    r = verifier_client.get(f"{IDENTITIES}/{record.pk}/photo/{record.selfie.pk}/")
    assert r.status_code == 200 and r.content == jpeg(2)
    assert r["Content-Type"] == "image/jpeg" and "no-store" in r["Cache-Control"]
    assert AdminAction.objects.filter(action="verification.view_photo").count() == 1

    # A photo can only be reached through the record it belongs to.
    assert verifier_client.get(f"{IDENTITIES}/{record.pk}/photo/{proof.photo.pk}/").status_code == 404
    assert verifier_client.get(f"{ADDRESSES}/{proof.pk}/photo/{proof.photo.pk}/").content == jpeg(10)


def test_confirm_identity_through_the_form(verifier_client, verifier, householder, jpeg):
    record = send_identity(householder, jpeg)
    r = verifier_client.post(f"{IDENTITIES}/{record.pk}/confirm/", IDENTITY_FORM, follow=True)
    assert "Identité confirmée." in r.content.decode()
    record.refresh_from_db()
    assert record.status == Status.CONFIRMED and record.reviewed_by == verifier
    html = verifier_client.get(f"{IDENTITIES}/{record.pk}/change/").content.decode()
    assert 'value="Confirmer"' not in html


def test_under_age_and_bad_date_show_french_errors_and_change_nothing(verifier_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    young = IDENTITY_FORM | {"date_of_birth": "2015-01-01"}
    r = verifier_client.post(f"{IDENTITIES}/{record.pk}/confirm/", young, follow=True)
    assert "La personne a moins de 18 ans." in r.content.decode()
    bad = IDENTITY_FORM | {"date_of_birth": "17/05/1990"}
    r = verifier_client.post(f"{IDENTITIES}/{record.pk}/confirm/", bad, follow=True)
    assert "Date invalide." in r.content.decode()
    record.refresh_from_db()
    assert record.status in (Status.SUBMITTED, Status.IN_REVIEW) and record.full_name == ""


def test_refuse_without_reason_shows_error_then_refuses_with_one(verifier_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    r = verifier_client.post(f"{IDENTITIES}/{record.pk}/refuse/", {"reason": " "}, follow=True)
    assert "Le motif est obligatoire." in r.content.decode()
    verifier_client.post(f"{IDENTITIES}/{record.pk}/refuse/", {"reason": "Photo floue"})
    record.refresh_from_db()
    assert (record.status, record.reason) == (Status.REFUSED, "Photo floue")


def test_address_page_shows_location_map_link_and_mock_warning(verifier_client, verifier, householder, jpeg):
    proof = send_address(householder, jpeg)
    html = verifier_client.get(f"{ADDRESSES}/{proof.pk}/change/").content.decode()
    assert "Identité non confirmée" in html and "Position non enregistrée" in html

    review.confirm_identity(send_identity(householder, jpeg), staff=verifier, **identity_values())
    send_location(householder, mock_location=True)
    r = verifier_client.get(f"{ADDRESSES}/{proof.pk}/change/")
    html = r.content.decode()
    assert "no-store" in r["Cache-Control"]
    assert "Kouassi Aya" in html and "Cocody" in html and "Angré 8e tranche" in html
    assert "https://www.openstreetmap.org/?mlat=5.3599&amp;mlon=-3.9871#map=17/5.3599/-3.9871" in html
    assert "Voir sur la carte" in html and "12 m" in html
    assert "Position simulée détectée" in html
    assert "Le nom correspond à l'identité confirmée" in html
    assert "L'adresse correspond à la commune, au quartier et à la position" in html


def test_confirm_address_through_the_form_makes_h1(verifier_client, verifier, householder, jpeg):
    review.confirm_identity(send_identity(householder, jpeg), staff=verifier, **identity_values())
    send_location(householder)
    proof = send_address(householder, jpeg)

    unticked = ADDRESS_FORM | {"issued_on": recent()}
    del unticked["address_consistent"]
    r = verifier_client.post(f"{ADDRESSES}/{proof.pk}/confirm/", unticked, follow=True)
    assert "Cochez les deux vérifications avant de confirmer." in r.content.decode()
    assert householder_tier(householder) == "H0"

    r = verifier_client.post(
        f"{ADDRESSES}/{proof.pk}/confirm/", ADDRESS_FORM | {"issued_on": recent()}, follow=True
    )
    assert "Justificatif confirmé." in r.content.decode()
    assert householder_tier(householder) == "H1"


def test_refuse_address_with_location(verifier_client, householder, jpeg):
    send_location(householder)
    proof = send_address(householder, jpeg)
    verifier_client.post(
        f"{ADDRESSES}/{proof.pk}/refuse/", {"reason": "Position loin du quartier", "refuse_location": "on"}
    )
    proof.refresh_from_db()
    assert proof.status == Status.REFUSED
    from apps.verification.models import HomeLocation

    assert HomeLocation.objects.get(user=householder).status == Status.REFUSED


def test_decisions_via_get_are_405(verifier_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    proof = send_address(householder, jpeg)
    for path in (
        f"{IDENTITIES}/{record.pk}/confirm/",
        f"{IDENTITIES}/{record.pk}/refuse/",
        f"{ADDRESSES}/{proof.pk}/confirm/",
        f"{ADDRESSES}/{proof.pk}/refuse/",
    ):
        assert verifier_client.get(path).status_code == 405, path


def test_records_cannot_be_added_changed_or_deleted_in_admin(verifier_client, householder, jpeg):
    record = send_identity(householder, jpeg)
    assert verifier_client.get(f"{IDENTITIES}/add/").status_code == 403
    assert verifier_client.post(f"{IDENTITIES}/{record.pk}/delete/", {"post": "yes"}).status_code == 403
    verifier_client.post(f"{IDENTITIES}/{record.pk}/change/", {"status": "confirmed"})
    record.refresh_from_db()
    assert record.status != Status.CONFIRMED


def test_address_values_helper_matches_form(householder):
    # Guards the two helpers against drifting apart.
    assert set(address_values()) - {"issued_on"} == set(ADDRESS_FORM) - {"issued_on"}
