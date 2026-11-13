from datetime import date

import pytest
from freezegun import freeze_time

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.verification.models import Guarantor, Status
from apps.verification.services import review, submissions
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError
from tests.test_guarantor_submissions import NOW, send

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def _fixed_day():
    with freeze_time("2026-11-12 10:00:00"):
        yield


def code(call):
    with pytest.raises(VerificationError) as caught:
        call()
    return caught.value.code


_counter = {"n": 0}


def new_jobber(jpeg, verifier, identity=True):
    _counter["n"] += 1
    n = _counter["n"]
    user = User.objects.create_user(phone=f"+22507070{n:05d}", role="jobber")
    if identity:
        record = submissions.submit_identity(
            user,
            document_type="cni",
            front=jpeg(n * 3),
            back=jpeg(n * 3 + 1),
            selfie=jpeg(n * 3 + 2),
            captured_at=NOW,
        )
        review.confirm_identity(
            record,
            staff=verifier,
            full_name="Jeune Jobber",
            date_of_birth=date(2001, 3, 4),
            document_number=f"CI-{n}",
            document_expires_on=date(2031, 1, 1),
        )
    return user


def sent(user, jpeg, **overrides):
    return send(user, jpeg, seed=100 + user.pk.int % 100, **overrides)


def call_done(record, verifier):
    review.record_call(
        record, staff=verifier, knows_jobber=True, confirms_residence=True, agrees_contact=True
    )


def confirm_values(**overrides):
    values = {
        "holder_name": "Kouassi Yao",
        "reference_number": "CIE-5566",
        "issued_on": date(2026, 10, 1),
        "name_matches": True,
    }
    values.update(overrides)
    return values


@pytest.mark.parametrize(
    "answers",
    [
        (False, True, True),
        (True, False, True),
        (True, True, False),
    ],
)
def test_call_requires_all_three_answers(jpeg, verifier, answers):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    knows, residence, agrees = answers
    assert (
        code(
            lambda: review.record_call(
                record,
                staff=verifier,
                knows_jobber=knows,
                confirms_residence=residence,
                agrees_contact=agrees,
            )
        )
        == "checks_required"
    )
    record.refresh_from_db()
    assert record.contacted_at is None


def test_call_is_recorded_and_moves_the_record_into_review(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    call_done(record, verifier)
    record.refresh_from_db()
    assert record.contacted_at and record.contacted_by == verifier
    assert record.status == Status.IN_REVIEW


def test_confirm_requires_identity_confirmed(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier, identity=False), jpeg)
    call_done(record, verifier)
    assert code(lambda: review.confirm_guarantor(record, staff=verifier, **confirm_values())) == (
        "identity_not_confirmed"
    )


def test_confirm_requires_a_recorded_call(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    assert code(lambda: review.confirm_guarantor(record, staff=verifier, **confirm_values())) == (
        "call_required"
    )


def test_confirm_requires_the_name_to_match(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    call_done(record, verifier)
    assert code(
        lambda: review.confirm_guarantor(
            record, staff=verifier, **confirm_values(name_matches=False)
        )
    ) == "checks_required"


def test_confirm_sets_dates_and_encrypts_fields(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values())
    record.refresh_from_db()
    assert record.status == Status.CONFIRMED and record.reviewed_by == verifier
    assert record.confirmed_at and record.expires_at.year == 2027
    assert "Kouassi" not in record.holder_name and "5566" not in record.reference_number
    assert decrypt_text(record.holder_name) == "Kouassi Yao"
    assert record.reference_hash


@pytest.mark.parametrize("issued", [date(2026, 6, 1), date(2026, 12, 1)])
def test_old_and_future_bills_are_refused(jpeg, verifier, issued):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    call_done(record, verifier)
    assert code(
        lambda: review.confirm_guarantor(record, staff=verifier, **confirm_values(issued_on=issued))
    ) == "proof_too_old"


def test_reference_cap_counts_confirmed_and_expired_of_other_users_only(jpeg, verifier, settings):
    settings.GUARANTOR_MAX_JOBBERS = 2
    first, second, third = (new_jobber(jpeg, verifier) for _ in range(3))
    for user in (first, second):
        record = sent(user, jpeg)
        call_done(record, verifier)
        review.confirm_guarantor(record, staff=verifier, **confirm_values())
    # An expired guarantor still holds its bill.
    Guarantor.objects.filter(user=second).update(status=Status.EXPIRED)
    record = sent(third, jpeg)
    call_done(record, verifier)
    assert code(lambda: review.confirm_guarantor(record, staff=verifier, **confirm_values())) == (
        "bill_reference_cap"
    )
    # Another reference is fine.
    review.confirm_guarantor(record, staff=verifier, **confirm_values(reference_number="OTHER-1"))


def test_the_same_jobber_can_renew_with_the_same_reference(jpeg, verifier, settings):
    settings.GUARANTOR_MAX_JOBBERS = 1
    user = new_jobber(jpeg, verifier)
    first = sent(user, jpeg)
    call_done(first, verifier)
    review.confirm_guarantor(first, staff=verifier, **confirm_values())
    Guarantor.objects.filter(pk=first.pk).update(status=Status.EXPIRED)
    again = send(user, jpeg, seed=250)
    call_done(again, verifier)
    review.confirm_guarantor(again, staff=verifier, **confirm_values())
    again.refresh_from_db()
    assert again.status == Status.CONFIRMED


def test_a_second_confirmation_of_the_same_record_is_refused(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values())
    assert code(lambda: review.confirm_guarantor(record, staff=verifier, **confirm_values())) == (
        "invalid_state"
    )


def test_refuse_needs_a_reason_and_keeps_it(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    assert code(lambda: review.refuse_guarantor(record, staff=verifier, reason="  ")) == "reason_required"
    review.refuse_guarantor(record, staff=verifier, reason="Le garant n'a pas répondu.")
    record.refresh_from_db()
    assert record.status == Status.REFUSED and record.reason == "Le garant n'a pas répondu."


def test_every_step_is_audited(jpeg, verifier):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    review.open_for_review(record, staff=verifier)
    review.record_view(record, staff=verifier)
    call_done(record, verifier)
    review.confirm_guarantor(record, staff=verifier, **confirm_values())
    actions = set(AdminAction.objects.values_list("action", flat=True))
    assert {
        "verification.guarantor.open",
        "verification.guarantor.view",
        "verification.guarantor.call",
        "verification.guarantor.confirm",
    } <= actions


def test_staff_without_the_permission_is_forbidden(jpeg, verifier, staff_user):
    record = sent(new_jobber(jpeg, verifier), jpeg)
    for call in (
        lambda: review.record_call(
            record, staff=staff_user, knows_jobber=True, confirms_residence=True, agrees_contact=True
        ),
        lambda: review.confirm_guarantor(record, staff=staff_user, **confirm_values()),
        lambda: review.refuse_guarantor(record, staff=staff_user, reason="x"),
    ):
        assert code(call) == "forbidden"
