"""Applications to offers: a jobber asks, the householder picks one. Every rule lives here; views
only translate HTTP."""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.services import record as audit
from apps.bookings.models import Application, Booking
from apps.listings.models import Offer
from apps.listings.services.screening import contact_in
from apps.verification.services.tiers import jobber_tier

from . import payments
from .errors import BookingError  # noqa: F401 - re-exported for the callers


def _require_jobber(user) -> None:
    if not (user and user.is_active and user.role == "jobber"):
        raise BookingError("forbidden")


def _offer_locked(offer_id) -> Offer:
    try:
        offer = Offer.objects.select_for_update().filter(pk=offer_id).first()
    except (ValidationError, ValueError):
        offer = None
    if offer is None:
        raise BookingError("offer_unavailable")
    return offer


def _clashes(user, offer: Offer) -> bool:
    """A live booking of this jobber that overlaps the offer's time."""
    end = offer.starts_at + timedelta(minutes=offer.duration_minutes)
    for booking in Booking.objects.filter(jobber=user, status__in=Booking.LIVE, starts_at__lt=end):
        if booking.starts_at + timedelta(minutes=booking.duration_minutes) > offer.starts_at:
            return True
    return False


def _lock_jobber(jobber_id) -> None:
    """Serialise everything that books or counts one jobber's time (apply and accept), whichever
    offers are involved. Always taken before an offer row, so the order never inverts."""
    User.objects.select_for_update().get(pk=jobber_id)


def _free(jobber, offer: Offer) -> None:
    """The jobber has no dispute open and no live booking that overlaps the offer."""
    if Booking.objects.filter(jobber=jobber, status=Booking.Status.DISPUTED).exists():
        raise BookingError("dispute_open")
    if _clashes(jobber, offer):
        raise BookingError("application_overlap")


def apply(user, offer_id, message: str) -> Application:
    """A J1 jobber applies to a published offer that has not started."""
    _require_jobber(user)
    if not payments.available():
        raise BookingError("payment_unavailable")
    if jobber_tier(user) != "J1":
        raise BookingError("jobber_verification_required")
    text = (message or "").strip()
    if len(text) > settings.APPLICATION_MESSAGE_MAX:
        raise BookingError("message_too_long")
    if text and contact_in(text):
        raise BookingError("message_contact_details")
    with transaction.atomic():
        _lock_jobber(user.pk)
        offer = _offer_locked(offer_id)
        if offer.status != Offer.Status.PUBLISHED or offer.starts_at <= timezone.now():
            raise BookingError("offer_unavailable")
        pending = Application.objects.filter(status=Application.Status.PENDING)
        live = Application.objects.filter(
            offer=offer, jobber=user, status__in=(Application.Status.PENDING, Application.Status.ACCEPTED)
        )
        if live.exists():
            raise BookingError("already_applied")
        if pending.filter(jobber=user).count() >= settings.APPLICATIONS_MAX_OPEN:
            raise BookingError("too_many_applications")
        if pending.filter(offer=offer).count() >= settings.APPLICATIONS_MAX_PER_OFFER:
            raise BookingError("offer_full")
        _free(user, offer)
        application = Application.objects.create(offer=offer, jobber=user, message=text)
        audit(user, "booking.application.apply", application)
    return application


def _own(user, application_id) -> Application:
    try:
        application = Application.objects.filter(pk=application_id, jobber=user).first()
    except (ValidationError, ValueError):
        application = None
    if application is None:
        raise BookingError("forbidden")
    return application


def withdraw(user, application_id) -> Application:
    _require_jobber(user)
    with transaction.atomic():
        row = Application.objects.select_for_update().filter(pk=_own(user, application_id).pk).get()
        if row.status != Application.Status.PENDING:
            raise BookingError("invalid_state")
        row.status = Application.Status.WITHDRAWN
        row.decided_at = timezone.now()
        row.save(update_fields=["status", "decided_at"])
        audit(user, "booking.application.withdraw", row)
    return row


def my_applications(user):
    """The jobber's applications, newest first."""
    _require_jobber(user)
    return Application.objects.filter(jobber=user).select_related("offer", "booking").order_by("-created_at")


def first_names(user_ids) -> dict:
    """The first word of the name staff confirmed on each jobber's identity document. A jobber
    without a confirmed identity has no entry: nothing is shown in their place."""
    from apps.verification.models import OPEN, IdentityVerification, Status
    from apps.verification.services.encryption import decrypt_text

    chosen: dict = {}
    # The record that counts is the open one if any, otherwise the most recent (as `current_record`).
    for record in IdentityVerification.objects.filter(user_id__in=list(user_ids)).order_by("-created_at"):
        held = chosen.get(record.user_id)
        if held is None or (held.status not in OPEN and record.status in OPEN):
            chosen[record.user_id] = record
    names = {}
    for user_id, record in chosen.items():
        if record.status == Status.CONFIRMED:
            words = decrypt_text(record.full_name).split()
            if words:
                names[user_id] = words[0]
    return names


def _jobs_done(**who) -> int:
    return Booking.objects.filter(status=Booking.Status.COMPLETED, **who).count()


def _jobs_done_by(user_ids) -> dict:
    rows = (
        Booking.objects.filter(status=Booking.Status.COMPLETED, jobber_id__in=list(user_ids))
        .values("jobber_id")
        .annotate(n=Count("id"))
    )
    return {row["jobber_id"]: row["n"] for row in rows}


def _owned_offer(user, offer_id) -> Offer:
    if not (user and user.is_active and user.role == "householder"):
        raise BookingError("forbidden")
    try:
        offer = Offer.objects.filter(pk=offer_id, author=user).first()
    except (ValidationError, ValueError):
        offer = None
    if offer is None:
        raise BookingError("forbidden")
    return offer


def applicants(user, offer_id) -> list[dict]:
    """What a householder sees of the people who applied: a first name, never a contact. Someone
    whose identity is no longer confirmed is not listed."""
    offer = _owned_offer(user, offer_id)
    pending = list(offer.applications.filter(status=Application.Status.PENDING).order_by("created_at"))
    ids = {application.jobber_id for application in pending}
    names = first_names(ids)
    done = _jobs_done_by(ids)
    return [
        {
            "id": application.pk,
            "first_name": names[application.jobber_id],
            "tier": "J1",
            "jobs_done": done.get(application.jobber_id, 0),
            "rating": None,
            "message": application.message,
            "created_at": application.created_at,
        }
        for application in pending
        if application.jobber_id in names
    ]


def householder_trust(householder) -> dict:
    """What a jobber sees of the householder before applying. No name, no contact."""
    from apps.verification.services.tiers import householder_tier

    return {
        "tier": householder_tier(householder),
        "jobs_done": _jobs_done(householder=householder),
        "rating": None,
    }


def accept(user, application_id, *, offer_id=None) -> Booking:
    """The householder picks one applicant: one booking, the others declined, the offer booked.
    With `offer_id`, the application must belong to that offer."""
    if not (user and user.is_active and user.role == "householder"):
        raise BookingError("forbidden")
    try:
        found = Application.objects.select_related("offer").filter(pk=application_id).first()
    except (ValidationError, ValueError):
        found = None
    if found is None or found.offer.author_id != user.pk:
        raise BookingError("forbidden")
    if not payments.available():
        raise BookingError("payment_unavailable")
    if offer_id is not None and str(found.offer_id) != str(offer_id):
        raise BookingError("forbidden")
    with transaction.atomic():
        _lock_jobber(found.jobber_id)
        offer = _offer_locked(found.offer_id)
        application = Application.objects.select_for_update().select_related("jobber").get(pk=found.pk)
        if application.status != Application.Status.PENDING:
            raise BookingError("invalid_state")
        if offer.status != Offer.Status.PUBLISHED or offer.starts_at <= timezone.now():
            raise BookingError("offer_unavailable")
        # Too late to pay and release the address before the start: the booking could only expire.
        if offer.starts_at - timedelta(hours=settings.ADDRESS_RELEASE_HOURS) <= timezone.now():
            raise BookingError("offer_unavailable")
        if jobber_tier(application.jobber) != "J1" or application.jobber_id not in first_names(
            [application.jobber_id]
        ):
            raise BookingError("applicant_not_verified")
        # The jobber may have taken another job, or opened a dispute, since applying.
        _free(application.jobber, offer)
        now = timezone.now()
        booking = Booking.objects.create(
            offer=offer,
            application=application,
            householder=user,
            jobber=application.jobber,
            category_name=offer.category_name,
            duties=list(offer.duties),
            starts_at=offer.starts_at,
            duration_minutes=offer.duration_minutes,
            pay_xof=offer.pay_xof,
            commune=offer.commune,
            quartier=offer.quartier,
        )
        application.status = Application.Status.ACCEPTED
        application.decided_at = now
        application.save(update_fields=["status", "decided_at"])
        offer.applications.filter(status=Application.Status.PENDING).update(
            status=Application.Status.DECLINED, decided_at=now
        )
        offer.status = Offer.Status.BOOKED
        offer.save(update_fields=["status", "updated_at"])
        audit(user, "booking.accept", booking)
    return booking


def close_stale() -> int:
    """Decline the pending applications of offers that are over: withdrawn, refused, closed, booked
    to someone else, or published but started. An offer still in review keeps its applications."""
    now = timezone.now()
    over = Q(
        offer__status__in=(
            Offer.Status.WITHDRAWN,
            Offer.Status.REFUSED,
            Offer.Status.CLOSED,
            Offer.Status.BOOKED,
        )
    ) | Q(offer__status=Offer.Status.PUBLISHED, offer__starts_at__lte=now)
    return (
        Application.objects.filter(status=Application.Status.PENDING)
        .filter(over)
        .update(status=Application.Status.DECLINED, decided_at=now)
    )
