import pytest
from django.utils import timezone

from apps.audit.models import AdminAction
from apps.verification.models import Status
from apps.verification.services import review
from tests.test_guarantor_review import new_jobber, sent

pytestmark = pytest.mark.django_db

GUARANTORS = "/admin/verification/guarantor"
CALL = {"knows_jobber": "on", "confirms_residence": "on", "agrees_contact": "on"}


def confirm_form(**overrides):
    form = {
        "holder_name": "Kouassi Yao",
        "reference_number": "CIE-5566",
        "issued_on": timezone.localdate().isoformat(),
        "name_matches": "on",
    }
    form.update(overrides)
    return form


@pytest.fixture
def record(jpeg, verifier):
    return sent(new_jobber(jpeg, verifier), jpeg)


def test_verifier_sees_the_queue_todo_first(verifier_client, verifier, record):
    page = verifier_client.get(f"{GUARANTORS}/").content.decode()
    assert record.user.phone in page and "Garants" in page
    review.refuse_guarantor(record, staff=verifier, reason="Illisible")
    assert record.user.phone not in verifier_client.get(f"{GUARANTORS}/").content.decode()
    assert record.user.phone in verifier_client.get(f"{GUARANTORS}/?etat=all").content.decode()


def test_the_review_page_shows_the_guarantor_and_audits_the_view(verifier_client, record):
    response = verifier_client.get(f"{GUARANTORS}/{record.pk}/change/")
    page = response.content.decode()
    assert "Kouassi Yao" in page and "+2250707070707" in page and "Parent" in page
    assert "Jeune Jobber" in page  # the confirmed identity to compare with
    assert "no-store" in response["Cache-Control"]
    record.refresh_from_db()
    assert record.status == Status.IN_REVIEW
    assert AdminAction.objects.filter(action="verification.guarantor.view").exists()


def test_call_confirm_flow_through_the_console(verifier_client, record):
    base = f"{GUARANTORS}/{record.pk}"
    assert verifier_client.post(f"{base}/call/", CALL).status_code == 302
    assert verifier_client.post(f"{base}/confirm/", confirm_form()).status_code == 302
    record.refresh_from_db()
    assert record.status == Status.CONFIRMED and record.contacted_at


def test_refuse_flow_through_the_console(verifier_client, record):
    verifier_client.post(f"{GUARANTORS}/{record.pk}/refuse/", {"reason": "Pas joignable"})
    record.refresh_from_db()
    assert record.status == Status.REFUSED and record.reason == "Pas joignable"


def test_confirming_before_the_call_shows_the_french_error(verifier_client, record):
    response = verifier_client.post(f"{GUARANTORS}/{record.pk}/confirm/", confirm_form(), follow=True)
    assert "Notez d&#x27;abord l&#x27;appel au garant." in response.content.decode()
    record.refresh_from_db()
    assert record.status != Status.CONFIRMED


def test_an_incomplete_call_form_is_refused(verifier_client, record):
    response = verifier_client.post(f"{GUARANTORS}/{record.pk}/call/", {"knows_jobber": "on"}, follow=True)
    assert "Cochez les trois réponses du garant" in response.content.decode()
    record.refresh_from_db()
    assert record.contacted_at is None


def test_the_bill_is_served_no_store_and_audited(verifier_client, record):
    response = verifier_client.get(f"{GUARANTORS}/{record.pk}/photo/{record.photo.pk}/")
    assert response.status_code == 200 and response["Content-Type"] == "image/jpeg"
    assert "no-store" in response["Cache-Control"]
    assert AdminAction.objects.filter(action="verification.view_photo").exists()


def test_an_enrolment_agent_gets_403_everywhere(agent_client, record):
    for path in (
        f"{GUARANTORS}/",
        f"{GUARANTORS}/{record.pk}/change/",
        f"{GUARANTORS}/{record.pk}/photo/{record.photo.pk}/",
    ):
        assert agent_client.get(path).status_code == 403, path
    for action, data in (("call", CALL), ("confirm", confirm_form()), ("refuse", {"reason": "x"})):
        assert agent_client.post(f"{GUARANTORS}/{record.pk}/{action}/", data).status_code == 403
    record.refresh_from_db()
    assert record.status == Status.SUBMITTED and record.contacted_at is None


def test_the_list_page_shows_no_encrypted_columns(verifier_client, record):
    page = verifier_client.get(f"{GUARANTORS}/?etat=all").content.decode()
    assert "Kouassi" not in page and "0707070707" not in page
    assert record.guarantor_name not in page
