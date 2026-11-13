from datetime import timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.verification import tasks
from apps.verification.models import ContactStatus, TrustedContact
from apps.verification.services import contacts, submissions
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError

pytestmark = pytest.mark.django_db

OWN = "+2250505050505"
A, B, C, D = "07 07 07 07 07", "01 01 01 01 01", "01 02 03 04 05", "07 08 09 09 09"


@pytest.fixture
def jobber():
    return User.objects.create_user(phone=OWN, role="jobber")


def code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


def add(user, phone=A, name="Awa Koné", relationship="parent"):
    return contacts.add_contact(user, name=name, phone=phone, relationship=relationship)


def replace(user, contact, phone=B, name="Yao Traoré", relationship="friend"):
    return contacts.replace_contact(user, contact.pk, name=name, phone=phone, relationship=relationship)


def confirmed(jobber, verifier, phone=A):
    contact = add(jobber, phone)
    value = contacts.send_code(contact, staff=verifier)
    return contacts.confirm_contact(jobber, contact.pk, value)


def age(contact, **fields):
    TrustedContact.objects.filter(pk=contact.pk).update(**fields)
    contact.refresh_from_db()
    return contact


def test_add_stores_encrypted_and_sends_nothing(jobber):
    contact = add(jobber)
    raw = TrustedContact.objects.filter(pk=contact.pk).values("name", "phone", "code_hash").get()
    assert "Awa" not in raw["name"] and "0707070707" not in raw["phone"] and "+225" not in raw["phone"]
    assert decrypt_text(raw["name"]) == "Awa Koné" and decrypt_text(raw["phone"]) == "+2250707070707"
    assert raw["code_hash"] == ""
    assert contact.status == ContactStatus.PENDING and contacts.awaiting_code(contact)


@pytest.mark.parametrize("phone", ["+2250505050505", "0505050505", "00225 05 05 05 05 05"])
def test_own_phone_is_refused_in_any_format(jobber, verifier, phone):
    assert code(lambda: add(jobber, phone)) == "contact_phone_own"
    confirmed_one = confirmed(jobber, verifier)
    assert code(lambda: replace(jobber, confirmed_one, phone)) == "contact_phone_own"


@pytest.mark.parametrize("phone", ["+2250707070707", "0707070707", "00225 07 07 07 07 07"])
def test_guarantor_phone_is_refused_in_any_format(jobber, jpeg, phone):
    submissions.submit_guarantor(
        jobber,
        document_type="facture_eau",
        photo=jpeg(30),
        guarantor_name="Kouassi Yao",
        guarantor_phone="07 07 07 07 07",
        relationship="parent",
        captured_at=timezone.now(),
    )
    assert code(lambda: add(jobber, phone)) == "contact_phone_guarantor"


def test_invalid_phone_name_and_relationship_each_have_their_code(jobber):
    assert code(lambda: add(jobber, "123")) == "contact_phone_invalid"
    assert code(lambda: add(jobber, name="  ")) == "contact_name_required"
    assert code(lambda: add(jobber, relationship="boss")) == "relationship_invalid"
    assert TrustedContact.objects.count() == 0


def test_name_is_capped_at_120_characters(jobber):
    contact = add(jobber, name="x" * 300)
    assert len(decrypt_text(contact.name)) == 120


def test_duplicate_phone_refused(jobber):
    add(jobber, A)
    assert code(lambda: add(jobber, "0707070707")) == "contact_phone_duplicate"


def test_cap_counts_pending_but_a_replacement_takes_no_extra_slot(jobber, verifier):
    first = confirmed(jobber, verifier, A)
    add(jobber, B)
    assert code(lambda: add(jobber, C)) == "contact_limit"
    replace(jobber, first, C)  # not refused by the cap
    assert code(lambda: add(jobber, D)) == "contact_limit"


def test_adds_per_day_cap_counts_replaced_contacts(jobber):
    one = add(jobber, A)
    two = replace(jobber, one, B)
    three = replace(jobber, two, C)
    assert TrustedContact.objects.filter(user=jobber).count() == 3
    assert code(lambda: replace(jobber, three, D)) == "rate_limited"


def test_send_code_needs_the_permission_stores_only_the_hash_and_audits(jobber, verifier):
    contact = add(jobber)
    outsider = User.objects.create_user(username="outsider", password="pw", role="staff", is_staff=True)
    assert code(lambda: contacts.send_code(contact, staff=outsider)) == "forbidden"
    value = contacts.send_code(contact, staff=verifier)
    contact.refresh_from_db()
    assert len(value) == 6 and value.isdigit()
    assert value not in contact.code_hash and len(contact.code_hash) == 64
    assert contact.code_sent_by == verifier and not contacts.awaiting_code(contact)
    assert AdminAction.objects.filter(action="verification.contact.send_code", actor=verifier).count() == 1


def test_send_code_twice_replaces_the_first_code(jobber, verifier):
    contact = add(jobber)
    first = contacts.send_code(contact, staff=verifier)
    second = contacts.send_code(contact, staff=verifier)
    if first == second:  # one in a million: make the test deterministic
        pytest.skip("same code twice")
    assert code(lambda: contacts.confirm_contact(jobber, contact.pk, first)) == "contact_code_invalid"
    assert contacts.confirm_contact(jobber, contact.pk, second).status == ContactStatus.CONFIRMED


def test_confirm_with_the_code_staff_sent(jobber, verifier):
    contact = confirmed(jobber, verifier)
    assert contact.status == ContactStatus.CONFIRMED and contact.confirmed_at and contact.code_hash == ""


def test_confirm_before_any_code_was_sent_is_refused(jobber):
    contact = add(jobber)
    assert code(lambda: contacts.confirm_contact(jobber, contact.pk, "123456")) == "contact_code_expired"


def test_wrong_code_counts_attempts_then_locks_until_a_new_code(jobber, verifier):
    contact = add(jobber)
    value = contacts.send_code(contact, staff=verifier)
    wrong = "000000" if value != "000000" else "111111"
    for _ in range(5):
        assert code(lambda: contacts.confirm_contact(jobber, contact.pk, wrong)) == "contact_code_invalid"
    assert code(lambda: contacts.confirm_contact(jobber, contact.pk, value)) == "contact_locked"
    fresh = contacts.send_code(contact, staff=verifier)
    assert contacts.confirm_contact(jobber, contact.pk, fresh).status == ContactStatus.CONFIRMED


def test_expired_code_refused(jobber, verifier):
    contact = add(jobber)
    value = contacts.send_code(contact, staff=verifier)
    age(contact, code_expires_at=timezone.now() - timedelta(minutes=1))
    assert code(lambda: contacts.confirm_contact(jobber, contact.pk, value)) == "contact_code_expired"


def test_request_code_waits_while_staff_have_not_sent_and_then_for_the_delay(jobber, verifier):
    contact = add(jobber)
    assert code(lambda: contacts.request_code(jobber, contact.pk)) == "contact_code_wait"
    contacts.send_code(contact, staff=verifier)
    assert code(lambda: contacts.request_code(jobber, contact.pk)) == "contact_code_wait"
    long_ago = timezone.now() - timedelta(hours=2)
    age(contact, code_requested_at=long_ago, code_sent_at=long_ago + timedelta(hours=1))
    again = contacts.request_code(jobber, contact.pk)
    assert contacts.awaiting_code(again)


def test_request_code_only_for_a_pending_contact(jobber, verifier):
    contact = confirmed(jobber, verifier)
    assert code(lambda: contacts.request_code(jobber, contact.pk)) == "invalid_state"


def test_replacing_a_pending_contact_is_immediate_and_keeps_the_confirmed_one(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    first = replace(jobber, old, B)
    second = replace(jobber, first, C)
    first.refresh_from_db()
    old.refresh_from_db()
    assert first.status == ContactStatus.REPLACED and first.replaced_at
    assert second.status == ContactStatus.PENDING and second.replaces_id == old.pk
    assert old.status == ContactStatus.CONFIRMED


def test_replacing_a_confirmed_contact_waits_for_confirmation_notice_and_delay(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    new = replace(jobber, old, B)
    assert new.replaces_id == old.pk
    assert contacts.apply_replacements(jobber) == 0
    value = contacts.send_code(new, staff=verifier)
    contacts.confirm_contact(jobber, new.pk, value)
    assert contacts.apply_replacements(jobber) == 0  # no notice yet
    contacts.record_notice(old, staff=verifier)
    assert contacts.apply_replacements(jobber) == 0  # the delay has not passed
    age(old, old_notified_at=timezone.now() - timedelta(hours=73))
    assert contacts.apply_replacements(jobber) == 1
    old.refresh_from_db()
    assert old.status == ContactStatus.REPLACED and old.replaced_at


def test_record_notice_rules_and_audit(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    assert code(lambda: contacts.record_notice(old, staff=verifier)) == "invalid_state"  # no replacement
    new = replace(jobber, old, B)
    assert code(lambda: contacts.record_notice(old, staff=verifier)) == "invalid_state"  # not confirmed
    contacts.confirm_contact(jobber, new.pk, contacts.send_code(new, staff=verifier))
    contacts.record_notice(old, staff=verifier)
    old.refresh_from_db()
    assert old.old_notified_by == verifier
    assert code(lambda: contacts.record_notice(old, staff=verifier)) == "invalid_state"
    assert AdminAction.objects.filter(action="verification.contact.notice").count() == 1


def test_no_notice_means_the_old_contact_stays(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    new = replace(jobber, old, B)
    contacts.confirm_contact(jobber, new.pk, contacts.send_code(new, staff=verifier))
    age(new, confirmed_at=timezone.now() - timedelta(days=30))
    assert contacts.apply_replacements(jobber) == 0
    old.refresh_from_db()
    assert old.status == ContactStatus.CONFIRMED


def test_confirmed_contact_with_a_live_replacement_cannot_be_replaced_again(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    replace(jobber, old, B)
    assert code(lambda: replace(jobber, old, C)) == "invalid_state"


def test_a_replaced_contact_cannot_be_replaced(jobber):
    one = add(jobber, A)
    replace(jobber, one, B)
    assert code(lambda: replace(jobber, one, C)) == "invalid_state"


def test_no_service_removes_a_contact():
    for name in ("remove_contact", "delete_contact", "retire_contact"):
        assert not hasattr(contacts, name)


def test_other_jobbers_contact_is_forbidden(jobber, verifier):
    other = User.objects.create_user(phone="+2250606060606", role="jobber")
    contact = add(jobber)
    assert code(lambda: contacts.request_code(other, contact.pk)) == "forbidden"
    assert code(lambda: contacts.confirm_contact(other, contact.pk, "123456")) == "forbidden"
    assert code(lambda: replace(other, contact)) == "forbidden"


def test_householder_and_inactive_user_forbidden(householder, jobber):
    assert code(lambda: add(householder)) == "forbidden"
    jobber.is_active = False
    jobber.save()
    assert code(lambda: add(jobber)) == "forbidden"


def test_apply_contact_replacements_task_sweeps_overdue(jobber, verifier):
    old = confirmed(jobber, verifier, A)
    new = replace(jobber, old, B)
    contacts.confirm_contact(jobber, new.pk, contacts.send_code(new, staff=verifier))
    contacts.record_notice(old, staff=verifier)
    age(old, old_notified_at=timezone.now() - timedelta(hours=80))
    assert tasks.apply_contact_replacements() == 1
