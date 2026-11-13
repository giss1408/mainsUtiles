import re
from urllib.parse import unquote

import pytest

from apps.audit.models import AdminAction
from apps.verification.models import ContactStatus, TrustedContact
from apps.verification.services import contacts
from tests.test_guarantor_review import new_jobber

pytestmark = pytest.mark.django_db

CONTACTS = "/admin/verification/trustedcontact"
NUMBER = "01 01 01 01 01"


@pytest.fixture
def jobber(jpeg, verifier):
    return new_jobber(jpeg, verifier)


@pytest.fixture
def contact(jobber):
    return contacts.add_contact(jobber, name="Awa Koné", phone=NUMBER, relationship="parent")


def code_in(response) -> str:
    """The code written in the WhatsApp link the page offers."""
    link = re.search(r'href="(https://wa\.me/[^"]+)"', response.content.decode()).group(1)
    return re.search(r"code : (\d{6})", unquote(link.replace("&amp;", "&"))).group(1)


def test_agent_sees_the_send_queue_first(verifier_client, verifier, contact):
    page = verifier_client.get(f"{CONTACTS}/").content.decode()
    assert contact.user.phone in page and "Personnes de confiance" in page
    contacts.send_code(contact, staff=verifier)
    assert contact.user.phone not in verifier_client.get(f"{CONTACTS}/").content.decode()
    assert contact.user.phone in verifier_client.get(f"{CONTACTS}/?file=all").content.decode()


def test_send_shows_the_link_once_with_the_code_and_the_number_and_audits(verifier_client, verifier, contact):
    response = verifier_client.post(f"{CONTACTS}/{contact.pk}/send/")
    assert response.status_code == 200 and "no-store" in response["Cache-Control"]
    page = response.content.decode()
    assert "https://wa.me/2250101010101?text=" in page and "Ouvrir WhatsApp" in page
    assert "Ne recopiez pas ce code" in page
    contact.refresh_from_db()
    assert (
        contacts.confirm_contact(contact.user, contact.pk, code_in(response)).status
        == ContactStatus.CONFIRMED
    )
    assert AdminAction.objects.filter(action="verification.contact.send_code", actor=verifier).exists()


def test_a_second_send_issues_a_new_code_and_the_old_one_stops_working(verifier_client, contact):
    first = code_in(verifier_client.post(f"{CONTACTS}/{contact.pk}/send/"))
    second = code_in(verifier_client.post(f"{CONTACTS}/{contact.pk}/send/"))
    if first == second:
        pytest.skip("same code twice")
    with pytest.raises(contacts.VerificationError) as caught:
        contacts.confirm_contact(contact.user, contact.pk, first)
    assert caught.value.code == "contact_code_invalid"


def test_the_review_page_audits_the_view_and_shows_no_phone_as_text(verifier_client, contact):
    response = verifier_client.get(f"{CONTACTS}/{contact.pk}/change/")
    page = response.content.decode()
    assert "Awa Koné" in page and "Parent" in page and "Jeune Jobber" in page
    assert "0101010101" not in page and "2250101010101" not in page and "01 01 01" not in page
    assert "Envoyer le code par WhatsApp" in page
    assert "no-store" in response["Cache-Control"]
    assert AdminAction.objects.filter(action="verification.contact.view").exists()


def test_the_notice_queue_marks_the_old_contact_notified_and_audits(verifier_client, verifier, jobber):
    old = contacts.add_contact(jobber, name="Awa Koné", phone=NUMBER, relationship="parent")
    contacts.confirm_contact(jobber, old.pk, contacts.send_code(old, staff=verifier))
    new = contacts.replace_contact(jobber, old.pk, name="Yao", phone="01 02 03 04 05", relationship="friend")
    contacts.confirm_contact(jobber, new.pk, contacts.send_code(new, staff=verifier))

    queue = verifier_client.get(f"{CONTACTS}/?file=notice").content.decode()
    assert jobber.phone in queue
    page = verifier_client.get(f"{CONTACTS}/{old.pk}/change/").content.decode()
    assert "Prévenir l&#x27;ancienne personne" in page or "Prévenir l'ancienne personne" in page

    response = verifier_client.post(f"{CONTACTS}/{old.pk}/notice/")
    assert response.status_code == 200 and "no-store" in response["Cache-Control"]
    link = unquote(re.search(r'href="(https://wa\.me/[^"]+)"', response.content.decode()).group(1))
    assert "wa.me/2250101010101" in link and "72 h" in link
    old.refresh_from_db()
    assert old.old_notified_by is not None
    assert AdminAction.objects.filter(action="verification.contact.notice", actor=verifier).exists()
    assert jobber.phone not in verifier_client.get(f"{CONTACTS}/?file=notice").content.decode()


def test_the_list_page_shows_no_encrypted_columns(verifier_client, contact):
    page = verifier_client.get(f"{CONTACTS}/?file=all").content.decode()
    assert "Awa" not in page and "0101010101" not in page
    assert "gAAAA" not in page  # not even the encrypted text


def test_an_enrolment_agent_gets_403_everywhere(agent_client, contact):
    for path in (f"{CONTACTS}/", f"{CONTACTS}/{contact.pk}/change/"):
        assert agent_client.get(path).status_code == 403, path
    for action in ("send", "notice"):
        assert agent_client.post(f"{CONTACTS}/{contact.pk}/{action}/").status_code == 403
    contact.refresh_from_db()
    assert contact.code_hash == ""


def test_sending_twice_after_the_contact_is_confirmed_shows_the_french_error(
    verifier_client, verifier, contact
):
    contacts.confirm_contact(contact.user, contact.pk, contacts.send_code(contact, staff=verifier))
    response = verifier_client.post(f"{CONTACTS}/{contact.pk}/send/", follow=True)
    assert "n&#x27;est plus à confirmer" in response.content.decode()
    assert TrustedContact.objects.get(pk=contact.pk).status == ContactStatus.CONFIRMED
