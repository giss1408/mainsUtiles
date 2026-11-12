import re
import uuid

import pytest
from django.test import Client

from apps.accounts.models import DeviceEnrolmentRequest, User
from apps.accounts.services.enrolment import apply, confirm
from apps.audit.models import AdminAction
from apps.audit.services import record

pytestmark = pytest.mark.django_db

BASE = "/admin/accounts/deviceenrolmentrequest"


def url(req, action="change"):
    return f"{BASE}/{req.id}/{action}/"


def test_agent_sees_queue_without_secret_fields(agent_client, pending_request):
    listing = agent_client.get(f"{BASE}/")
    assert listing.status_code == 200 and "+2250708091011" in listing.content.decode()
    html = agent_client.get(url(pending_request)).content.decode()
    assert "Approuver" in html and "Refuser" in html and "Mettre en attente" in html
    assert "code_hash" not in html and "client_token_hash" not in html
    assert "Envoyer par WhatsApp" not in html


def test_approve_then_send_shows_whatsapp_link_with_working_code(agent_client, pending_request, settings):
    settings.OFFICIAL_WHATSAPP_NUMBER = "+2250700000000"
    r = agent_client.post(url(pending_request, "approve"))
    assert r.status_code == 302
    assert "Envoyer par WhatsApp" in agent_client.get(url(pending_request)).content.decode()

    r = agent_client.post(url(pending_request, "send"))
    html = r.content.decode()
    assert r.status_code == 200
    assert "no-store" in r["Cache-Control"]
    assert "https://wa.me/2250708091011?text=petitGombo" in html
    assert "Ouvrir WhatsApp" in html and "+2250700000000" in html
    code = re.search(r"confirmation%20est%20(\d{6})", html).group(1)
    assert html.count(code) == 1
    assert confirm(pending_request, client_token="tok", code=code).status == "active"
    assert "Renvoyer par WhatsApp" not in agent_client.get(url(pending_request)).content.decode()


def test_code_sent_request_offers_resend(agent_client, pending_request):
    agent_client.post(url(pending_request, "approve"))
    agent_client.post(url(pending_request, "send"))
    assert "Renvoyer par WhatsApp" in agent_client.get(url(pending_request)).content.decode()


def test_actions_via_get_are_405(agent_client, pending_request):
    for action in ("approve", "refuse", "hold", "send"):
        assert agent_client.get(url(pending_request, action)).status_code == 405
    pending_request.refresh_from_db()
    assert pending_request.status == "pending"


def test_staff_outside_group_gets_403_on_approve_and_send(pending_request, staff_user):
    outsider = User.objects.create_user(username="other", password="pw", role="staff", is_staff=True)
    client = Client()
    client.force_login(outsider)
    assert client.post(url(pending_request, "approve")).status_code == 403
    assert client.post(url(pending_request, "send")).status_code == 403
    pending_request.refresh_from_db()
    assert pending_request.status == "pending" and AdminAction.objects.count() == 0


def test_anonymous_user_is_sent_to_login(pending_request):
    r = Client().post(url(pending_request, "approve"))
    assert r.status_code == 302 and "/admin/login/" in r["Location"]


def test_refuse_requires_reason(agent_client, pending_request):
    r = agent_client.post(url(pending_request, "refuse"), {"reason": "  "}, follow=True)
    assert "Le motif est obligatoire." in r.content.decode()
    pending_request.refresh_from_db()
    assert pending_request.status == "pending"

    agent_client.post(url(pending_request, "refuse"), {"reason": "Numéro injoignable"})
    pending_request.refresh_from_db()
    assert (pending_request.status, pending_request.reason) == ("refused", "Numéro injoignable")


def test_hold_records_reason(agent_client, pending_request):
    agent_client.post(url(pending_request, "hold"), {"reason": "À rappeler"})
    pending_request.refresh_from_db()
    assert (pending_request.status, pending_request.reason) == ("held", "À rappeler")


def test_second_agent_approving_sees_error_and_single_audit_row(agent_client, pending_request):
    agent_client.post(url(pending_request, "approve"))
    r = agent_client.post(url(pending_request, "approve"), follow=True)
    assert "Cette demande ne peut plus être modifiée." in r.content.decode()
    assert AdminAction.objects.filter(action="enrolment.approve").count() == 1


def test_new_device_approval_shows_selfie_required_message(agent_client, enrol_device):
    enrol_device()
    req = apply(
        phone="0708091011",
        role="jobber",
        device_id=uuid.uuid4(),
        device_model="Itel",
        platform="android",
        public_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        client_token="tok",
    )
    r = agent_client.post(url(req, "approve"), follow=True)
    assert "selfie" in r.content.decode()
    req.refresh_from_db()
    assert req.status == "pending"


def test_requests_cannot_be_added_changed_or_deleted_in_admin(agent_client, pending_request):
    assert agent_client.get(f"{BASE}/add/").status_code == 403
    assert agent_client.post(url(pending_request, "delete"), {"post": "yes"}).status_code == 403
    agent_client.post(url(pending_request), {"status": "completed", "phone": "+2250000000000"})
    pending_request.refresh_from_db()
    assert (pending_request.status, pending_request.phone) == ("pending", "+2250708091011")
    assert DeviceEnrolmentRequest.objects.count() == 1


def test_admin_actions_are_read_only(staff_user):
    admin = User.objects.create_superuser(username="root", password="pw")
    client = Client()
    client.force_login(admin)
    action = record(staff_user, "enrolment.approve", staff_user)
    base = "/admin/audit/adminaction"
    assert client.get(f"{base}/").status_code == 200
    assert client.get(f"{base}/{action.pk}/change/").status_code == 200
    assert client.get(f"{base}/add/").status_code == 403
    assert client.post(f"{base}/{action.pk}/delete/", {"post": "yes"}).status_code == 403
    assert AdminAction.objects.count() == 1


def test_superuser_can_open_staff_user_pages():
    admin = User.objects.create_superuser(username="root", password="pw")
    client = Client()
    client.force_login(admin)
    assert client.get("/admin/accounts/user/").status_code == 200
    assert client.get("/admin/accounts/user/add/").status_code == 200
