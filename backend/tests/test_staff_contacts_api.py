import re
from datetime import timedelta
from urllib.parse import unquote

import pytest
from django.contrib.auth.models import Group
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.verification.models import ContactStatus
from apps.verification.services import contacts
from tests.test_guarantor_review import new_jobber

pytestmark = pytest.mark.django_db

BASE = "/api/v1/staff/contacts"
NUMBER = "01 01 01 01 01"


@pytest.fixture
def jobber(jpeg, verifier):
    return new_jobber(jpeg, verifier)


@pytest.fixture
def contact(jobber):
    return contacts.add_contact(jobber, name="Awa Koné", phone=NUMBER, relationship="parent")


@pytest.fixture
def api(verifier):
    client = APIClient()
    client.force_authenticate(verifier)
    return client


def code_in(response) -> str:
    link = response.json()["whatsapp_url"]
    return re.search(r"code : (\d{6})", unquote(link)).group(1)


def confirmed_with_replacement(jobber, staff):
    old = contacts.add_contact(jobber, name="Vieux", phone=NUMBER, relationship="parent")
    contacts.confirm_contact(jobber, old.pk, _send_and_code(old, staff))
    new = contacts.replace_contact(jobber, old.pk, name="Neuf", phone="05 05 05 05 05", relationship="friend")
    contacts.confirm_contact(jobber, new.pk, _send_and_code(new, staff))
    old.refresh_from_db()
    return old


def _send_and_code(contact, staff):
    return contacts.send_code(contact, staff=staff)


def test_the_send_queue_lists_contacts_awaiting_a_code_without_any_phone_or_name(api, contact, jobber):
    rows = api.get(BASE).json()["results"]
    assert [r["id"] for r in rows] == [str(contact.pk)]
    row = rows[0]
    assert row["action"] == "send" and row["relationship"] == "parent"
    raw = str(row)
    assert "Awa" not in raw and "0101010101" not in raw and jobber.phone not in raw


def test_the_queue_empties_once_the_code_is_sent_and_returns_on_a_new_request(api, verifier, contact):
    contacts.send_code(contact, staff=verifier)
    assert api.get(BASE).json()["results"] == []
    contact.refresh_from_db()
    aged = timezone.now() - timedelta(hours=1)
    contact.code_sent_at = contact.code_requested_at = aged
    contact.save(update_fields=["code_sent_at", "code_requested_at"])
    contacts.request_code(contact.user, contact.pk)
    assert len(api.get(BASE).json()["results"]) == 1


def test_the_notice_queue_lists_confirmed_contacts_being_replaced(api, verifier, jobber):
    old = confirmed_with_replacement(jobber, verifier)
    rows = api.get(f"{BASE}?file=notice").json()["results"]
    assert [(r["id"], r["action"]) for r in rows] == [(str(old.pk), "notice")]
    assert api.get(BASE).json()["results"] == []


def test_detail_shows_the_name_and_the_confirmed_identity_and_audits_the_view(api, contact):
    body = api.get(f"{BASE}/{contact.pk}").json()
    assert body["name"] == "Awa Koné" and body["relationship"] == "parent"
    assert body["jobber_name"] and "phone" not in body
    assert "0101010101" not in str(body)
    assert AdminAction.objects.filter(action="verification.contact.view").exists()


def test_send_returns_the_link_once_with_the_code_and_audits(api, verifier, contact):
    response = api.post(f"{BASE}/{contact.pk}/send")
    assert response.status_code == 200 and "no-store" in response["Cache-Control"]
    assert response.json()["whatsapp_url"].startswith("https://wa.me/2250101010101?text=")
    assert (
        contacts.confirm_contact(contact.user, contact.pk, code_in(response)).status
        == ContactStatus.CONFIRMED
    )
    assert AdminAction.objects.filter(action="verification.contact.send_code", actor=verifier).exists()
    assert api.get(BASE).json()["results"] == []


def test_send_for_a_confirmed_contact_is_refused(api, verifier, contact):
    contacts.confirm_contact(contact.user, contact.pk, contacts.send_code(contact, staff=verifier))
    response = api.post(f"{BASE}/{contact.pk}/send")
    assert response.status_code == 409


def test_notice_returns_the_link_to_the_old_number_and_starts_the_delay(api, verifier, jobber):
    old = confirmed_with_replacement(jobber, verifier)
    response = api.post(f"{BASE}/{old.pk}/notice")
    assert response.status_code == 200 and "no-store" in response["Cache-Control"]
    assert response.json()["whatsapp_url"].startswith("https://wa.me/2250101010101?text=")
    old.refresh_from_db()
    assert old.old_notified_at is not None
    assert AdminAction.objects.filter(action="verification.contact.notice", actor=verifier).exists()
    assert api.post(f"{BASE}/{old.pk}/notice").status_code == 409


def test_staff_without_the_permission_and_app_users_get_403(jobber, contact):
    other = User.objects.create_user(username="agent2", password="pw", role="staff", is_staff=True)
    other.groups.add(Group.objects.get(name="enrolment_agent"))
    client = APIClient()
    client.force_authenticate(other)
    for call in (
        client.get(BASE),
        client.get(f"{BASE}/{contact.pk}"),
        client.post(f"{BASE}/{contact.pk}/send"),
        client.post(f"{BASE}/{contact.pk}/notice"),
    ):
        assert call.status_code == 403
    client.force_authenticate(jobber)
    assert client.get(BASE).status_code == 403


def test_unknown_contact_is_404_and_the_list_is_no_store(api):
    assert api.get(f"{BASE}/00000000-0000-0000-0000-000000000000").status_code == 404
    assert "no-store" in api.get(BASE)["Cache-Control"]
