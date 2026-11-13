"""Trusted contacts. A jobber names them; staff send each one a code on WhatsApp; the jobber types
the code the contact reads out. A contact is never deleted, only replaced by another one who goes
through the same check. Every rule lives here; views only translate HTTP."""

import hashlib
import hmac
import secrets
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import F, Q
from django.utils import timezone

from apps.accounts.models import User
from apps.accounts.phones import InvalidPhone, normalise
from apps.audit.services import record as audit
from apps.verification.models import ContactStatus, Guarantor, Status, TrustedContact

from .encryption import encrypt_text, keyed_hash
from .submissions import VerificationError, _require_jobber

SEND_CODE = "verification.send_contact_code"
LIVE = (ContactStatus.PENDING, ContactStatus.CONFIRMED)

CONTACT_MESSAGE = (
    "petitGombo : quelqu'un vous a choisi comme personne de confiance. Si vous acceptez, "
    "donnez-lui ce code : {code}. Sinon, ignorez ce message. "
    "Notre équipe ne vous demandera jamais ce code."
)
NOTICE_MESSAGE = (
    "petitGombo : vous serez remplacé(e) dans {n} h comme personne de confiance d'un mini-jobber. "
    "Si vous ne connaissez pas cette personne, répondez à ce message."
)


def _hash_code(pk, code: str) -> str:
    return hmac.new(settings.SECRET_KEY.encode(), f"{pk}:{code}".encode(), hashlib.sha256).hexdigest()


def _require_staff(staff) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(SEND_CODE)):
        raise VerificationError("forbidden")


def live_contacts(user):
    return TrustedContact.objects.filter(user=user, status__in=LIVE)


def awaiting_code(contact: TrustedContact) -> bool:
    """The jobber asked for a code and staff have not sent one since."""
    return contact.status == ContactStatus.PENDING and (
        contact.code_sent_at is None or contact.code_sent_at < contact.code_requested_at
    )


def own(user, contact_id) -> TrustedContact:
    try:
        contact = TrustedContact.objects.filter(pk=contact_id, user=user).first()
    except (ValidationError, ValueError):
        contact = None
    if contact is None:
        raise VerificationError("forbidden")
    return contact


def send_queue():
    """Pending contacts staff still have to send a code to, oldest first."""
    return (
        TrustedContact.objects.filter(status=ContactStatus.PENDING)
        .filter(Q(code_sent_at__isnull=True) | Q(code_sent_at__lt=F("code_requested_at")))
        .order_by("created_at", "pk")
    )


def notice_queue():
    """Confirmed contacts being replaced whose number has not been warned yet, oldest first."""
    replaced = TrustedContact.objects.filter(status=ContactStatus.CONFIRMED, replaces__isnull=False).values(
        "replaces_id"
    )
    return TrustedContact.objects.filter(
        status=ContactStatus.CONFIRMED, old_notified_at__isnull=True, pk__in=replaced
    ).order_by("created_at", "pk")


def _locked(contact: TrustedContact) -> TrustedContact:
    return TrustedContact.objects.select_for_update().get(pk=contact.pk)


def _replacement_of(contact: TrustedContact):
    return TrustedContact.objects.filter(replaces=contact, status__in=LIVE).first()


def _checked(user, *, name, phone, relationship, ignore=None) -> tuple[str, str]:
    """Validate what the jobber typed. Returns the cleaned name and the E.164 phone."""
    name = (name or "").strip()
    if not name:
        raise VerificationError("contact_name_required")
    if relationship not in TrustedContact.Relationship.values:
        raise VerificationError("relationship_invalid")
    try:
        number = normalise(phone)
    except InvalidPhone as exc:
        raise VerificationError("contact_phone_invalid") from exc
    if user.phone and number == normalise(user.phone):
        raise VerificationError("contact_phone_own")
    digest = keyed_hash(number)
    if (
        Guarantor.objects.filter(user=user, guarantor_phone_hash=digest)
        .exclude(status=Status.REFUSED)
        .exists()
    ):
        raise VerificationError("contact_phone_guarantor")
    others = TrustedContact.objects.filter(user=user, phone_hash=digest).exclude(
        status=ContactStatus.REPLACED
    )
    if ignore is not None:
        others = others.exclude(pk=ignore.pk)
    if others.exists():
        raise VerificationError("contact_phone_duplicate")
    return name[:120], number


def _rate_limited(user) -> bool:
    since = timezone.now() - timedelta(hours=24)
    return TrustedContact.objects.filter(user=user, created_at__gte=since).count() >= (
        settings.TRUSTED_CONTACT_MAX_ADDS_PER_DAY
    )


def _create(user, *, name, number, relationship, replaces=None) -> TrustedContact:
    return TrustedContact.objects.create(
        user=user,
        name=encrypt_text(name),
        phone=encrypt_text(number),
        phone_hash=keyed_hash(number),
        relationship=relationship,
        replaces=replaces,
        code_requested_at=timezone.now(),
    )


def add_contact(user, *, name: str, phone: str, relationship: str) -> TrustedContact:
    """A new pending contact. Nothing is sent: staff send the code."""
    _require_jobber(user)
    with transaction.atomic():
        User.objects.select_for_update().get(pk=user.pk)  # one add at a time per jobber
        name, number = _checked(user, name=name, phone=phone, relationship=relationship)
        live = live_contacts(user)
        taken = live.exclude(replaces__isnull=True).values("replaces_id")
        if live.exclude(pk__in=taken).count() >= settings.TRUSTED_CONTACTS_MAX:
            raise VerificationError("contact_limit")
        if _rate_limited(user):
            raise VerificationError("rate_limited")
        return _create(user, name=name, number=number, relationship=relationship)


def replace_contact(user, contact_id, *, name: str, phone: str, relationship: str) -> TrustedContact:
    """A new pending contact that takes over from `contact_id`, with the same checks."""
    _require_jobber(user)
    with transaction.atomic():
        User.objects.select_for_update().get(pk=user.pk)
        target = _locked(own(user, contact_id))
        if target.status not in LIVE:
            raise VerificationError("invalid_state")
        if target.status == ContactStatus.CONFIRMED and _replacement_of(target):
            raise VerificationError("invalid_state")
        pending = target.status == ContactStatus.PENDING
        name, number = _checked(
            user, name=name, phone=phone, relationship=relationship, ignore=target if pending else None
        )
        if _rate_limited(user):
            raise VerificationError("rate_limited")
        replaces = target
        if pending:
            # A number never confirmed can simply be changed: the confirmed contact behind it stays.
            replaces = target.replaces
            target.status = ContactStatus.REPLACED
            target.replaced_at = timezone.now()
            target.save(update_fields=["status", "replaced_at"])
        return _create(user, name=name, number=number, relationship=relationship, replaces=replaces)


def request_code(user, contact_id) -> TrustedContact:
    """The jobber asks staff for a (new) code."""
    _require_jobber(user)
    with transaction.atomic():
        contact = _locked(own(user, contact_id))
        if contact.status != ContactStatus.PENDING:
            raise VerificationError("invalid_state")
        wait = timedelta(seconds=settings.TRUSTED_CONTACT_RESEND_SECONDS)
        if awaiting_code(contact) or (contact.code_sent_at and timezone.now() - contact.code_sent_at < wait):
            raise VerificationError("contact_code_wait")
        contact.code_requested_at = timezone.now()
        contact.save(update_fields=["code_requested_at"])
        return contact


def confirm_contact(user, contact_id, code: str) -> TrustedContact:
    """The jobber types the code the contact read out."""
    _require_jobber(user)
    error = None
    with transaction.atomic():
        contact = _locked(own(user, contact_id))
        if contact.status != ContactStatus.PENDING:
            raise VerificationError("invalid_state")
        if not contact.code_hash:
            error = "contact_code_expired"
        elif contact.code_attempts >= settings.TRUSTED_CONTACT_CODE_MAX_ATTEMPTS:
            error = "contact_locked"
        elif contact.code_expires_at is None or contact.code_expires_at <= timezone.now():
            error = "contact_code_expired"
        elif not hmac.compare_digest(contact.code_hash, _hash_code(contact.pk, (code or "").strip())):
            contact.code_attempts += 1
            contact.save(update_fields=["code_attempts"])
            error = "contact_code_invalid"  # the attempt is kept: raise after the commit
        else:
            contact.status = ContactStatus.CONFIRMED
            contact.confirmed_at = timezone.now()
            contact.code_hash = ""
            contact.code_attempts = 0
            contact.save(update_fields=["status", "confirmed_at", "code_hash", "code_attempts"])
    if error:
        raise VerificationError(error)
    return contact


def send_code(contact: TrustedContact, *, staff) -> str:
    """Staff are about to send a code on WhatsApp. Returns it once; only its hash is stored."""
    _require_staff(staff)
    with transaction.atomic():
        row = _locked(contact)
        # Only a code the jobber asked for: a double tap or a replay must not cancel the one already sent.
        if row.status != ContactStatus.PENDING or not awaiting_code(row):
            raise VerificationError("invalid_state")
        code = f"{secrets.randbelow(10**6):06d}"
        now = timezone.now()
        row.code_hash = _hash_code(row.pk, code)
        row.code_attempts = 0
        row.code_sent_at = now
        row.code_sent_by = staff
        row.code_expires_at = now + timedelta(minutes=settings.TRUSTED_CONTACT_CODE_TTL_MINUTES)
        row.save(
            update_fields=["code_hash", "code_attempts", "code_sent_at", "code_sent_by", "code_expires_at"]
        )
        audit(staff, "verification.contact.send_code", row)
    contact.refresh_from_db()
    return code


def record_notice(contact: TrustedContact, *, staff) -> None:
    """Staff are about to warn the number being replaced; the delay counts from now."""
    _require_staff(staff)
    with transaction.atomic():
        row = _locked(contact)
        replacement = TrustedContact.objects.filter(replaces=row, status=ContactStatus.CONFIRMED).exists()
        if row.status != ContactStatus.CONFIRMED or row.old_notified_at or not replacement:
            raise VerificationError("invalid_state")
        row.old_notified_at = timezone.now()
        row.old_notified_by = staff
        row.save(update_fields=["old_notified_at", "old_notified_by"])
        audit(staff, "verification.contact.notice", row)
    contact.refresh_from_db()


def apply_replacements(user=None) -> int:
    """Retire the contacts whose confirmed replacement has had its notice and delay."""
    now = timezone.now()
    cutoff = now - timedelta(hours=settings.TRUSTED_CONTACT_CHANGE_DELAY_HOURS)
    replaced = TrustedContact.objects.filter(status=ContactStatus.CONFIRMED, replaces__isnull=False)
    due = TrustedContact.objects.filter(
        status=ContactStatus.CONFIRMED,
        old_notified_at__lte=cutoff,
        pk__in=replaced.values("replaces_id"),
    )
    if user is not None:
        due = due.filter(user=user)
    return due.update(status=ContactStatus.REPLACED, replaced_at=now)


def ends_at(contact: TrustedContact):
    """When a confirmed contact stops counting: its replacement confirmed, its number was warned."""
    if contact.status == ContactStatus.CONFIRMED and contact.old_notified_at:
        return contact.old_notified_at + timedelta(hours=settings.TRUSTED_CONTACT_CHANGE_DELAY_HOURS)
    return None
