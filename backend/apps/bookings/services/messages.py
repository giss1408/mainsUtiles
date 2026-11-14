"""Messages to users, sent by staff on WhatsApp from the staff app. The backend decides what is
said and to whom; staff only press send. A message never carries an address, a full name, a number
or a payment reference, and one that is no longer true is dropped instead of sent."""

from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Message
from apps.listings.models import Offer
from apps.providers import registry

from .errors import BookingError

SEND = "bookings.send_message"
K = Message.Kind
URGENT = (K.PAY_REMINDER, K.ADDRESS_AVAILABLE)

_PAID = (Booking.Status.CONFIRMED, Booking.Status.ADDRESS_RELEASED)

# What is said, by kind and by the recipient's role. `{job}` is the category and the start.
_TEXTS = {
    (K.APPLICANT, "householder"): (
        "vous avez un candidat pour votre offre {job}. Ouvrez l'application petitGombo pour le voir."
    ),
    (K.ACCEPTED, "jobber"): (
        "tu as été accepté(e) pour le job {job}. Il sera confirmé quand le ménage aura payé. "
        "Ouvre l'application petitGombo pour suivre."
    ),
    (K.PAY_REMINDER, "householder"): (
        "votre réservation {job} attend votre paiement. Sans paiement, elle sera annulée. "
        "Ouvrez l'application petitGombo pour payer."
    ),
    (K.PAYMENT_CONFIRMED, "householder"): (
        "votre paiement est confirmé pour {job}. Ouvrez l'application petitGombo pour voir qui vient."
    ),
    (K.PAYMENT_REFUSED, "householder"): (
        "votre preuve de paiement pour {job} n'a pas été acceptée. Ouvrez l'application petitGombo "
        "pour voir pourquoi et en envoyer une autre."
    ),
    (K.JOB_CONFIRMED, "jobber"): (
        "le job {job} est confirmé. L'adresse exacte sera dans l'application petitGombo quelques "
        "heures avant le début."
    ),
    (K.ADDRESS_AVAILABLE, "jobber"): (
        "l'adresse du job {job} est disponible. Ouvre l'application petitGombo pour la voir."
    ),
    (K.CONFIRM_JOB, "householder"): (
        "le jobber a terminé {job}. Ouvrez l'application petitGombo pour confirmer que c'est fait, "
        "ou pour signaler un problème."
    ),
    (K.PAID, "jobber"): (
        "ton paiement pour le job {job} a été envoyé. Ouvre l'application petitGombo pour le vérifier."
    ),
    (K.CANCELLED, "householder"): (
        "le jobber a annulé sa participation à {job}. Si vous avez payé, nous vous remboursons. "
        "Ouvrez l'application petitGombo pour la suite."
    ),
    (K.CANCELLED, "jobber"): (
        "le ménage a annulé le job {job}. Ouvre l'application petitGombo pour voir d'autres offres."
    ),
    (K.NO_SHOW, "householder"): (
        "le jobber ne s'est pas présenté pour {job}. La réservation est annulée et nous vous remboursons."
    ),
    (K.EXPIRED, "jobber"): (
        "le job {job} est annulé : le ménage n'a pas payé à temps. Ouvre l'application petitGombo "
        "pour voir d'autres offres."
    ),
    (K.REFUNDED, "householder"): (
        "votre remboursement pour {job} a été envoyé. Vérifiez votre compte de paiement mobile."
    ),
    (K.DISPUTE_OPENED, "householder"): (
        "un problème a été signalé pour {job}. Le paiement est gelé le temps que notre équipe "
        "regarde. Nous revenons vers vous."
    ),
    (K.DISPUTE_OPENED, "jobber"): (
        "un problème a été signalé pour le job {job}. Le paiement est gelé le temps que notre "
        "équipe regarde. Nous revenons vers toi."
    ),
    (K.DISPUTE_RESOLVED, "householder"): (
        "notre équipe a rendu sa décision pour {job}. Ouvrez l'application petitGombo pour voir la suite."
    ),
    (K.DISPUTE_RESOLVED, "jobber"): (
        "notre équipe a rendu sa décision pour le job {job}. Ouvre l'application petitGombo pour "
        "voir la suite."
    ),
    (K.REVIEW_INVITE, "householder"): (
        "{job} est terminé. Ouvrez l'application petitGombo pour donner votre avis sur le jobber."
    ),
    (K.REVIEW_INVITE, "jobber"): (
        "le job {job} est terminé. Ouvre l'application petitGombo pour donner ton avis sur le ménage."
    ),
}


def _require_staff(staff) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(SEND)):
        raise BookingError("forbidden")


def _subject(message: Message):
    """The booking when there is one, otherwise the offer: both name a category and a start."""
    return message.booking if message.booking_id else message.offer


def _job(message: Message) -> str:
    subject = _subject(message)
    start = timezone.localtime(subject.starts_at)
    return f"{subject.category_name} du {start:%d/%m} à {start:%H:%M}"


def queue(kind, *, to, booking: Booking | None = None, offer: Offer | None = None) -> Message | None:
    """Adds a message for staff to send. Nothing is added twice while one is still waiting, and a
    kind that has no wording for this recipient is ignored: queuing must never break the caller."""
    if to is None or (kind, to.role) not in _TEXTS:
        return None
    offer_id = booking.offer_id if booking is not None else offer.pk
    found = Message.objects.filter(
        offer_id=offer_id, recipient=to, kind=kind, status=Message.Status.PENDING
    ).first()
    if found is not None:
        return found
    try:
        with transaction.atomic():  # a savepoint: a lost race must not poison the caller's transaction
            return Message.objects.create(
                offer_id=offer_id, booking=booking, recipient=to, kind=kind, urgent=kind in URGENT
            )
    except IntegrityError:
        return Message.objects.filter(
            offer_id=offer_id, recipient=to, kind=kind, status=Message.Status.PENDING
        ).first()


def retire(kind, *, offer_id) -> int:
    """Withdraws the waiting messages of a kind once the person has already acted on them."""
    return Message.objects.filter(offer_id=offer_id, kind=kind, status=Message.Status.PENDING).update(
        status=Message.Status.DROPPED
    )


def text_of(message: Message) -> str:
    return "petitGombo : " + _TEXTS[(message.kind, message.recipient.role)].format(job=_job(message))


def still_true(message: Message, now=None) -> bool:
    """Whether the message still describes the booking. A stale one is dropped, never sent."""
    now = now or timezone.now()
    kind = message.kind
    if kind == K.APPLICANT:
        from apps.bookings.models import Application

        waiting = Application.objects.filter(offer=message.offer, status=Application.Status.PENDING)
        return message.offer.status == Offer.Status.PUBLISHED and waiting.exists()
    booking = message.booking
    if booking is None:
        return False
    status = booking.status
    if kind == K.ACCEPTED:
        return status in (Booking.Status.ACCEPTED, Booking.Status.PAYMENT_REVIEW)
    if kind in (K.PAY_REMINDER, K.PAYMENT_REFUSED):
        return status == Booking.Status.ACCEPTED
    if kind in (K.PAYMENT_CONFIRMED, K.JOB_CONFIRMED):
        return status in _PAID
    if kind == K.ADDRESS_AVAILABLE:
        end = booking.starts_at + timedelta(minutes=booking.duration_minutes)
        return status in _PAID and now < end
    if kind == K.CONFIRM_JOB:
        return status == Booking.Status.COMPLETION_PENDING
    if kind == K.DISPUTE_OPENED:
        return status == Booking.Status.DISPUTED
    if kind == K.REVIEW_INVITE:
        from . import reviews

        return reviews.reviewable(booking, message.recipient, now)
    return True


def send_queue():
    """Messages waiting for staff: the urgent ones first, then the oldest."""
    return (
        Message.objects.filter(status=Message.Status.PENDING)
        .select_related("offer", "booking", "recipient")
        .order_by("-urgent", "created_at", "pk")
    )


def late_after(message: Message) -> timedelta:
    minutes = settings.MESSAGE_URGENT_LATE_MINUTES if message.urgent else settings.MESSAGE_LATE_MINUTES
    return timedelta(minutes=minutes)


def is_late(message: Message, now=None) -> bool:
    now = now or timezone.now()
    return message.status == Message.Status.PENDING and now - message.created_at > late_after(message)


def preview(message: Message, *, staff) -> dict:
    """What staff are about to send. No number: it only travels inside the link."""
    _require_staff(staff)
    audit(staff, "booking.message.view", message, kind=message.kind)
    return {"text": text_of(message), "category_name": _subject(message).category_name}


def send(message: Message, *, staff) -> str:
    """Staff are about to send the message. Returns the WhatsApp link once and marks it sent. A
    message that is no longer true is dropped, and the caller is told so."""
    _require_staff(staff)
    now = timezone.now()
    with transaction.atomic():
        row = (
            Message.objects.select_for_update(of=("self",))
            .select_related("offer", "booking", "recipient")
            .get(pk=message.pk)
        )
        if row.status != Message.Status.PENDING:
            raise BookingError("invalid_state")
        stale = not still_true(row, now) or not row.recipient.phone
        row.status = Message.Status.DROPPED if stale else Message.Status.SENT
        row.sent_by = staff
        row.sent_at = now
        row.save(update_fields=["status", "sent_by", "sent_at"])
        audit(staff, "booking.message.drop" if stale else "booking.message.send", row, kind=row.kind)
        link = None if stale else registry.get_messaging().whatsapp_link(row.recipient.phone, text_of(row))
    message.refresh_from_db()
    if link is None:
        raise BookingError("message_stale")  # raised after the drop is committed
    return link


# ---- Messages that time, not a person, brings about ---------------------------------------------


def queue_pay_reminders(now=None) -> int:
    """Unpaid bookings whose time to pay is nearly over."""
    from .payments import pay_deadline

    now = now or timezone.now()
    count = 0
    for booking in Booking.objects.filter(status=Booking.Status.ACCEPTED).select_related("householder"):
        deadline = pay_deadline(booking)
        if not deadline - timedelta(hours=settings.PAYMENT_REMINDER_HOURS) <= now < deadline:
            continue
        if _already(booking, K.PAY_REMINDER, booking.householder):
            continue
        queue(K.PAY_REMINDER, booking=booking, to=booking.householder)
        count += 1
    return count


def queue_address_available(now=None) -> int:
    """Paid bookings whose address window has opened."""
    from .bookings import available_from

    now = now or timezone.now()
    count = 0
    for booking in Booking.objects.filter(status__in=_PAID).select_related("jobber"):
        end = booking.starts_at + timedelta(minutes=booking.duration_minutes)
        if not available_from(booking) <= now < end:
            continue
        if _already(booking, K.ADDRESS_AVAILABLE, booking.jobber):
            continue
        queue(K.ADDRESS_AVAILABLE, booking=booking, to=booking.jobber)
        count += 1
    return count


def _already(booking: Booking, kind, recipient) -> bool:
    """A sweep says a thing once per booking, whatever became of the message."""
    return Message.objects.filter(booking=booking, kind=kind, recipient=recipient).exists()


def queue_due() -> int:
    return queue_pay_reminders() + queue_address_available()
