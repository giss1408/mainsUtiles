"""Stage 4: the message model, the service, and the hooks at each booking event."""

from datetime import timedelta

import pytest
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.models import AdminAction
from apps.bookings.models import Booking, Message, Payment
from apps.bookings.services import applications, bookings, jobs, messages, payments, payouts, reports
from apps.bookings.services.errors import BookingError
from tests.helpers import accepted_booking, confirmed_booking, j1_jobber, make_offer, paid_booking

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("payment_method")]
K = Message.Kind


def code(call):
    with pytest.raises(BookingError) as caught:
        call()
    return caught.value.code


def kinds(**filters):
    return sorted(Message.objects.filter(**filters).values_list("kind", flat=True))


def one(kind, to):
    return Message.objects.get(kind=kind, recipient=to)


@pytest.fixture
def agent():
    user = User.objects.create_user(username="sender", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="payment_agent"))
    return user


@pytest.fixture
def outsider():
    return User.objects.create_user(username="nobody", password="pw", role="staff", is_staff=True)


@pytest.fixture
def accepted(verified_householder, jpeg, verifier):
    return accepted_booking(verified_householder, jpeg, verifier)


@pytest.fixture
def confirmed(verified_householder, jpeg, verifier):
    return confirmed_booking(verified_householder, jpeg, verifier)


def working(booking):
    Booking.objects.filter(pk=booking.pk).update(starts_at=timezone.now() + timedelta(minutes=5))
    return jobs.check_in(booking.jobber, booking.pk, lat=None, lng=None)


# ---- Model ----


def test_one_pending_message_per_offer_recipient_and_kind(accepted):
    with pytest.raises(IntegrityError), transaction.atomic():
        Message.objects.create(
            offer=accepted.offer, booking=accepted, recipient=accepted.jobber, kind=K.ACCEPTED
        )


def test_a_sent_message_allows_a_new_one(accepted):
    Message.objects.filter(kind=K.ACCEPTED).update(status=Message.Status.SENT)
    assert messages.queue(K.ACCEPTED, booking=accepted, to=accepted.jobber).status == Message.Status.PENDING
    assert Message.objects.filter(kind=K.ACCEPTED).count() == 2


def test_both_groups_can_send_messages():
    for name in ("payment_agent", "enrolment_agent"):
        codenames = set(Group.objects.get(name=name).permissions.values_list("codename", flat=True))
        assert {"send_message", "view_message"} <= codenames


# ---- Service ----


def test_queue_is_idempotent_while_pending(accepted):
    first = one(K.ACCEPTED, accepted.jobber)
    assert messages.queue(K.ACCEPTED, booking=accepted, to=accepted.jobber).pk == first.pk
    assert messages.queue(K.ACCEPTED, booking=accepted, to=None) is None
    # No wording for a householder being "accepted": ignored, never an error.
    assert messages.queue(K.ACCEPTED, booking=accepted, to=accepted.householder) is None
    assert Message.objects.filter(kind=K.ACCEPTED).count() == 1


def test_every_kind_has_a_text_without_sensitive_data(confirmed):
    sides = {"householder": confirmed.householder, "jobber": confirmed.jobber}
    seen = set()
    for (kind, role), _ in messages._TEXTS.items():
        row = Message(offer=confirmed.offer, booking=confirmed, recipient=sides[role], kind=kind)
        text = messages.text_of(row)
        seen.add(kind)
        assert text.startswith("petitGombo : ") and "Ménage du " in text and "{" not in text
        for secret in (confirmed.jobber.phone, confirmed.householder.phone, "Jeune", "Jobber", "WAVE-123456"):
            assert secret not in text
        assert confirmed.quartier not in text and confirmed.commune not in text
    assert seen == set(K.values)


def test_householder_texts_say_vous_and_jobber_texts_say_tu():
    for (_kind, role), text in messages._TEXTS.items():
        words = set(text.replace("'", " ").replace(",", " ").replace(".", " ").split())
        if role == "householder":
            assert not words & {"tu", "ton", "ta", "toi", "Ouvre"}, text
        else:
            assert not words & {"vous", "votre", "vos", "Ouvrez", "Vérifiez"}, text


def test_send_returns_a_link_to_the_recipient_and_marks_sent(accepted, agent):
    message = one(K.ACCEPTED, accepted.jobber)
    assert messages.preview(message, staff=agent)["category_name"] == "Ménage"
    assert accepted.jobber.phone not in str(messages.preview(message, staff=agent))
    link = messages.send(message, staff=agent)
    assert link.startswith(f"https://wa.me/{accepted.jobber.phone.lstrip('+')}?text=petitGombo")
    assert message.status == Message.Status.SENT and message.sent_by == agent and message.sent_at
    assert AdminAction.objects.filter(action="booking.message.send", actor=agent).count() == 1
    assert AdminAction.objects.filter(action="booking.message.view", actor=agent).count() == 2
    assert accepted.jobber.phone not in str(list(AdminAction.objects.values()))


def test_a_stale_message_is_dropped_not_sent(accepted, agent):
    message = one(K.ACCEPTED, accepted.jobber)
    bookings.cancel(accepted.householder, accepted.pk)
    assert code(lambda: messages.send(message, staff=agent)) == "message_stale"
    message.refresh_from_db()
    assert message.status == Message.Status.DROPPED
    assert AdminAction.objects.filter(action="booking.message.drop").exists()
    assert not AdminAction.objects.filter(action="booking.message.send").exists()
    assert message not in list(messages.send_queue())


def test_sending_twice_is_invalid_state(accepted, agent):
    message = one(K.ACCEPTED, accepted.jobber)
    messages.send(message, staff=agent)
    assert code(lambda: messages.send(message, staff=agent)) == "invalid_state"
    assert AdminAction.objects.filter(action="booking.message.send").count() == 1


def test_without_the_permission_nothing_is_sent(accepted, outsider):
    message = one(K.ACCEPTED, accepted.jobber)
    assert code(lambda: messages.send(message, staff=outsider)) == "forbidden"
    assert code(lambda: messages.preview(message, staff=outsider)) == "forbidden"
    assert code(lambda: messages.send(message, staff=accepted.jobber)) == "forbidden"
    message.refresh_from_db()
    assert message.status == Message.Status.PENDING


def test_urgent_first_then_oldest_and_late_markers(accepted, settings):
    old = one(K.ACCEPTED, accepted.jobber)
    urgent = messages.queue(K.PAY_REMINDER, booking=accepted, to=accepted.householder)
    assert urgent.urgent and not old.urgent
    assert [m.kind for m in messages.send_queue()][0] == K.PAY_REMINDER
    now = timezone.now()
    assert not messages.is_late(urgent, now) and not messages.is_late(old, now)
    after = now + timedelta(minutes=settings.MESSAGE_URGENT_LATE_MINUTES + 1)
    assert messages.is_late(urgent, after) and not messages.is_late(old, after)
    assert messages.is_late(old, now + timedelta(minutes=settings.MESSAGE_LATE_MINUTES + 1))


# ---- Hooks ----


def test_first_application_tells_the_householder_once(verified_householder, jpeg, verifier):
    offer = make_offer(verified_householder)
    applications.apply(j1_jobber(jpeg, verifier), offer.pk, "")
    message = one(K.APPLICANT, verified_householder)
    assert message.booking is None and message.offer == offer
    assert "vous avez un candidat" in messages.text_of(message)
    assert kinds() == ["applicant"] and messages.still_true(message)
    second = j1_jobber(jpeg, verifier)
    applications.apply(second, offer.pk, "")
    assert kinds() == ["applicant"]  # one message, however many candidates
    applications.accept(verified_householder, offer.applications.first().pk)
    message.refresh_from_db()
    assert message.status == Message.Status.DROPPED  # the householder has already chosen


def test_accept_tells_the_jobber(accepted):
    assert kinds(recipient=accepted.jobber) == ["accepted"]


def test_confirm_tells_both_and_refuse_tells_the_householder(verified_householder, jpeg, verifier, agent):
    booking, payment = paid_booking(verified_householder, jpeg, verifier)
    payments.refuse_payment(payment, staff=agent, reason="Montant différent")
    assert "payment_refused" in kinds(recipient=verified_householder)
    booking.refresh_from_db()
    assert messages.still_true(one(K.PAYMENT_REFUSED, verified_householder))
    confirmed = confirmed_booking(
        verified_householder, jpeg, verifier, days=4, seed=11, reference="WAVE-999000"
    )
    assert "payment_confirmed" in kinds(booking=confirmed, recipient=verified_householder)
    assert "job_confirmed" in kinds(booking=confirmed, recipient=confirmed.jobber)


def test_check_out_asks_the_householder_to_confirm(confirmed):
    working(confirmed)
    jobs.check_out(confirmed.jobber, confirmed.pk)
    message = one(K.CONFIRM_JOB, confirmed.householder)
    assert messages.still_true(message)
    jobs.confirm_done(confirmed.householder, confirmed.pk)
    message.refresh_from_db()
    assert not messages.still_true(message)


def test_completion_invites_both_to_review(confirmed):
    working(confirmed)
    jobs.check_out(confirmed.jobber, confirmed.pk)
    jobs.confirm_done(confirmed.householder, confirmed.pk)
    assert Message.objects.filter(kind=K.REVIEW_INVITE).count() == 2
    invite = one(K.REVIEW_INVITE, confirmed.jobber)
    assert messages.still_true(invite)
    from apps.bookings.services import reviews

    reviews.submit_review(confirmed.jobber, confirmed.pk, stars=5, comment="")
    assert not messages.still_true(Message.objects.get(pk=invite.pk))


def test_payout_tells_the_jobber(confirmed, agent):
    working(confirmed)
    jobs.check_out(confirmed.jobber, confirmed.pk)
    payout = jobs.confirm_done(confirmed.householder, confirmed.pk).payout
    payouts.record_payout(payout, staff=agent, reference="MOMO-998877")
    assert "ton paiement" in messages.text_of(one(K.PAID, confirmed.jobber))


def test_cancel_tells_the_other_side(verified_householder, jpeg, verifier):
    first = accepted_booking(verified_householder, jpeg, verifier)
    bookings.cancel(first.jobber, first.pk)
    assert "le jobber a annulé" in messages.text_of(one(K.CANCELLED, verified_householder))
    second = accepted_booking(verified_householder, jpeg, verifier, days=4)
    bookings.cancel(verified_householder, second.pk)
    assert "le ménage a annulé" in messages.text_of(one(K.CANCELLED, second.jobber))


def test_no_show_and_expiry_and_refund(verified_householder, jpeg, verifier, agent):
    confirmed = confirmed_booking(verified_householder, jpeg, verifier)
    assert jobs.close_no_shows(timezone.now() + timedelta(days=10)) == 1
    assert one(K.NO_SHOW, verified_householder).booking == confirmed
    payments.record_refund(Payment.objects.get(booking=confirmed), staff=agent, reference="RMB-12345")
    assert one(K.REFUNDED, verified_householder)
    unpaid = accepted_booking(verified_householder, jpeg, verifier, days=5)
    assert bookings.expire_unpaid(timezone.now() + timedelta(days=10)) == 1
    assert one(K.EXPIRED, unpaid.jobber).booking == unpaid


def test_a_dispute_tells_the_other_side_and_a_concern_tells_nobody(confirmed):
    working(confirmed)
    before = Message.objects.count()
    reports.report_problem(confirmed.jobber, confirmed.pk, text="Le chien mord", dispute=False)
    assert Message.objects.count() == before
    reports.report_problem(confirmed.householder, confirmed.pk, text="Rien de fait", dispute=True)
    assert kinds(kind=K.DISPUTE_OPENED) == ["dispute_opened"]
    message = one(K.DISPUTE_OPENED, confirmed.jobber)
    assert "Rien de fait" not in messages.text_of(message) and messages.still_true(message)


def test_resolution_tells_both(confirmed, agent):
    working(confirmed)
    report = reports.report_problem(confirmed.householder, confirmed.pk, text="Rien de fait", dispute=True)
    reports.resolve_dispute(report, staff=agent, outcome="split", note="Moitié", jobber_xof=1000)
    assert Message.objects.filter(kind=K.DISPUTE_RESOLVED).count() == 2
    assert Message.objects.filter(kind=K.REVIEW_INVITE).count() == 2
    assert not messages.still_true(one(K.DISPUTE_OPENED, confirmed.jobber))


def test_an_unclosed_job_tells_both(confirmed):
    working(confirmed)
    assert jobs.flag_unclosed(timezone.now() + timedelta(days=3)) == 1
    assert Message.objects.filter(kind=K.DISPUTE_OPENED).count() == 2


def test_reminder_and_address_sweeps_queue_once(verified_householder, jpeg, verifier, settings):
    unpaid = accepted_booking(verified_householder, jpeg, verifier)
    deadline = payments.pay_deadline(unpaid)
    assert (
        messages.queue_pay_reminders(deadline - timedelta(hours=settings.PAYMENT_REMINDER_HOURS, minutes=5))
        == 0
    )
    soon = deadline - timedelta(hours=1)
    assert messages.queue_pay_reminders(soon) == 1 and messages.queue_pay_reminders(soon) == 0
    reminder = one(K.PAY_REMINDER, verified_householder)
    assert reminder.urgent
    Message.objects.filter(pk=reminder.pk).update(status=Message.Status.SENT)
    assert messages.queue_pay_reminders(soon) == 0  # said once per booking

    paid = confirmed_booking(verified_householder, jpeg, verifier, days=4, seed=11, reference="WAVE-999000")
    opens = bookings.available_from(paid)
    assert messages.queue_address_available(opens - timedelta(minutes=1)) == 0
    assert messages.queue_address_available(opens + timedelta(minutes=1)) == 1
    assert messages.queue_address_available(opens + timedelta(minutes=2)) == 0
    address = one(K.ADDRESS_AVAILABLE, paid.jobber)
    assert address.urgent and messages.still_true(address, opens + timedelta(minutes=1))
    assert not messages.still_true(address, paid.starts_at + timedelta(days=1))
    from apps.bookings import tasks

    assert tasks.queue_due_messages() >= 0
