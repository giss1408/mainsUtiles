"""Staff decisions on verifications. Every rule a decision must respect lives here."""

import calendar
from datetime import date, datetime

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.verification.models import (
    UNDECIDED,
    AddressProof,
    Guarantor,
    HomeLocation,
    IdentityVerification,
    Status,
    VerificationPhoto,
)

from .encryption import encrypt_text, keyed_hash
from .submissions import VerificationError, read_photo_bytes
from .tiers import current_record

REVIEW = "verification.review_verification"
VIEW_PHOTO = "verification.view_verification_photo"


def _require(staff, permission: str) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(permission)):
        raise VerificationError("forbidden")


def _locked(record):
    """Re-read the row under a lock so two staff members cannot decide the same record."""
    return type(record).objects.select_for_update().get(pk=record.pk)


def _require_undecided(row) -> None:
    if row.status not in UNDECIDED:
        raise VerificationError("invalid_state")


def _text(value: str) -> str:
    value = (value or "").strip()
    if not value:
        raise VerificationError("field_required")
    return value


def _reason(value: str) -> str:
    value = (value or "").strip()
    if not value:
        raise VerificationError("reason_required")
    return value


def _shift_months(moment, months: int):
    """The same day `months` later (or earlier), clamped to the end of a shorter month."""
    index = moment.year * 12 + (moment.month - 1) + months
    year, month = divmod(index, 12)
    day = min(moment.day, calendar.monthrange(year, month + 1)[1])
    return moment.replace(year=year, month=month + 1, day=day)


def _age(born: date, today: date) -> int:
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def _decided(row, staff, status: str, now: datetime) -> None:
    row.status = status
    row.reviewed_by = staff
    row.reviewed_at = now


def _kind(record) -> str:
    if isinstance(record, IdentityVerification):
        return "identity"
    return "guarantor" if isinstance(record, Guarantor) else "address"


@transaction.atomic
def open_for_review(record, *, staff) -> None:
    """Mark a submitted record as being looked at. Does nothing in any other state."""
    _require(staff, REVIEW)
    row = _locked(record)
    if row.status != Status.SUBMITTED:
        return
    row.status = Status.IN_REVIEW
    row.save(update_fields=["status"])
    if isinstance(row, AddressProof):
        HomeLocation.objects.filter(user=row.user, status=Status.SUBMITTED).update(status=Status.IN_REVIEW)
    audit(staff, f"verification.{_kind(row)}.open", row)
    record.refresh_from_db()


def record_view(record, *, staff) -> None:
    """Leave an audit row each time a review page, with its names and position, is shown."""
    _require(staff, REVIEW)
    audit(staff, f"verification.{_kind(record)}.view", record)


def confirm_identity(
    record: IdentityVerification,
    *,
    staff,
    full_name: str,
    date_of_birth: date,
    document_number: str,
    document_expires_on: date,
) -> None:
    _require(staff, REVIEW)
    full_name, document_number = _text(full_name), _text(document_number)
    today = timezone.localdate()
    number_hash = keyed_hash(document_number)
    try:
        with transaction.atomic():
            row = _locked(record)
            _require_undecided(row)
            if _age(date_of_birth, today) < settings.MINIMUM_AGE_YEARS:
                raise VerificationError("under_age")
            if document_expires_on < today:
                raise VerificationError("document_expired")
            # One identity document backs one account.
            if (
                IdentityVerification.objects.filter(status=Status.CONFIRMED, document_number_hash=number_hash)
                .exclude(user=row.user)
                .exists()
            ):
                raise VerificationError("duplicate_document")
            row.full_name = encrypt_text(full_name)
            row.date_of_birth = encrypt_text(date_of_birth.isoformat())
            row.document_number = encrypt_text(document_number)
            row.document_number_hash = number_hash
            row.document_expires_on = document_expires_on
            _decided(row, staff, Status.CONFIRMED, timezone.now())
            row.save()
            audit(staff, "verification.identity.confirm", row)
    except IntegrityError as exc:
        # Two staff confirmed the same number on two accounts at once; the database kept one.
        raise VerificationError("duplicate_document") from exc
    record.refresh_from_db()


@transaction.atomic
def refuse_identity(record: IdentityVerification, *, staff, reason: str) -> None:
    _require(staff, REVIEW)
    reason = _reason(reason)
    row = _locked(record)
    _require_undecided(row)
    row.reason = reason
    _decided(row, staff, Status.REFUSED, timezone.now())
    row.save(update_fields=["reason", "status", "reviewed_by", "reviewed_at"])
    audit(staff, "verification.identity.refuse", row, reason=reason)
    record.refresh_from_db()


def confirm_address(
    record: AddressProof,
    *,
    staff,
    holder_name: str,
    reference_number: str,
    issued_on: date,
    name_matches: bool,
    address_consistent: bool,
    location_id,
) -> None:
    """Confirm a proof of address and, with it, the home position it was judged against.

    `location_id` is the position the staff member had on screen. The householder may record a
    new one until the decision, so a position staff never saw must not be confirmed.
    """
    _require(staff, REVIEW)
    today = timezone.localdate()
    try:
        with transaction.atomic():
            row = _locked(record)
            _require_undecided(row)
            identity = current_record(IdentityVerification, row.user)
            if identity is None or identity.status != Status.CONFIRMED:
                raise VerificationError("identity_not_confirmed")
            location = (
                HomeLocation.objects.select_for_update().filter(user=row.user, status__in=UNDECIDED).first()
            )
            if location is None:
                raise VerificationError("location_missing")
            if str(location.pk) != str(location_id):
                raise VerificationError("location_changed")
            holder_name, reference_number = _text(holder_name), _text(reference_number)
            oldest = _shift_months(today, -settings.ADDRESS_PROOF_MAX_AGE_MONTHS)
            if issued_on > today or issued_on < oldest:
                raise VerificationError("proof_too_old")
            if not (name_matches and address_consistent):
                raise VerificationError("checks_required")
            reference_hash = keyed_hash(reference_number)
            # One bill or certificate backs one householder. An expired proof still holds its
            # number: customer numbers do not change, and the owner will renew with the same one.
            if (
                AddressProof.objects.filter(
                    status__in=(Status.CONFIRMED, Status.EXPIRED), reference_hash=reference_hash
                )
                .exclude(user=row.user)
                .exists()
            ):
                raise VerificationError("duplicate_reference")
            now = timezone.now()
            row.holder_name = encrypt_text(holder_name)
            row.reference_number = encrypt_text(reference_number)
            row.reference_hash = reference_hash
            row.issued_on = issued_on
            row.confirmed_at = now
            row.expires_at = _shift_months(now, settings.ADDRESS_PROOF_VALID_MONTHS)
            _decided(row, staff, Status.CONFIRMED, now)
            row.save()
            _decided(location, staff, Status.CONFIRMED, now)
            location.save(update_fields=["status", "reviewed_by", "reviewed_at"])
            audit(staff, "verification.address.confirm", row, home_location=str(location.pk))
    except IntegrityError as exc:
        raise VerificationError("duplicate_reference") from exc
    record.refresh_from_db()


@transaction.atomic
def refuse_address(record: AddressProof, *, staff, reason: str, refuse_location: bool = False) -> None:
    """Refuse a proof of address; with `refuse_location`, the recorded home position as well."""
    _require(staff, REVIEW)
    reason = _reason(reason)
    row = _locked(record)
    _require_undecided(row)
    now = timezone.now()
    row.reason = reason
    _decided(row, staff, Status.REFUSED, now)
    row.save(update_fields=["reason", "status", "reviewed_by", "reviewed_at"])
    if refuse_location:
        HomeLocation.objects.filter(user=row.user, status__in=UNDECIDED).update(
            status=Status.REFUSED, reason=reason, reviewed_by=staff, reviewed_at=now
        )
    audit(staff, "verification.address.refuse", row, reason=reason, location_refused=refuse_location)
    record.refresh_from_db()


def read_photo(photo: VerificationPhoto, *, staff) -> bytes:
    """Return the decrypted image. Every view leaves an audit row."""
    _require(staff, VIEW_PHOTO)
    data = read_photo_bytes(photo)
    audit(staff, "verification.view_photo", photo, kind=photo.kind)
    return data


@transaction.atomic
def record_call(
    record: Guarantor, *, staff, knows_jobber: bool, confirms_residence: bool, agrees_contact: bool
) -> None:
    """Note that staff phoned the guarantor and what the guarantor answered."""
    _require(staff, REVIEW)
    row = _locked(record)
    _require_undecided(row)
    if not (knows_jobber and confirms_residence and agrees_contact):
        raise VerificationError("call_answers_required")
    now = timezone.now()
    row.contacted_at = now
    row.contacted_by = staff
    row.status = Status.IN_REVIEW
    row.save(update_fields=["contacted_at", "contacted_by", "status"])
    audit(staff, "verification.guarantor.call", row)
    record.refresh_from_db()


def confirm_guarantor(
    record: Guarantor,
    *,
    staff,
    holder_name: str,
    reference_number: str,
    issued_on: date,
    name_matches: bool,
) -> None:
    _require(staff, REVIEW)
    today = timezone.localdate()
    try:
        with transaction.atomic():
            row = _locked(record)
            _require_undecided(row)
            identity = current_record(IdentityVerification, row.user)
            if identity is None or identity.status != Status.CONFIRMED:
                raise VerificationError("identity_not_confirmed")
            if row.contacted_at is None:
                raise VerificationError("call_required")
            holder_name, reference_number = _text(holder_name), _text(reference_number)
            if not name_matches:
                raise VerificationError("checks_required")
            oldest = _shift_months(today, -settings.GUARANTOR_BILL_MAX_AGE_MONTHS)
            if issued_on > today or issued_on < oldest:
                raise VerificationError("proof_too_old")
            reference_hash = keyed_hash(reference_number)
            backed = (
                Guarantor.objects.filter(
                    status__in=(Status.CONFIRMED, Status.EXPIRED), reference_hash=reference_hash
                )
                .exclude(user=row.user)
                .values("user_id")
                .distinct()
                .count()
            )
            if backed >= settings.GUARANTOR_MAX_JOBBERS:
                raise VerificationError("bill_reference_cap")
            now = timezone.now()
            row.holder_name = encrypt_text(holder_name)
            row.reference_number = encrypt_text(reference_number)
            row.reference_hash = reference_hash
            row.issued_on = issued_on
            row.confirmed_at = now
            row.expires_at = _shift_months(now, settings.GUARANTOR_VALID_MONTHS)
            _decided(row, staff, Status.CONFIRMED, now)
            row.save()
            audit(staff, "verification.guarantor.confirm", row)
    except IntegrityError as exc:
        raise VerificationError("invalid_state") from exc
    record.refresh_from_db()


@transaction.atomic
def refuse_guarantor(record: Guarantor, *, staff, reason: str) -> None:
    _require(staff, REVIEW)
    reason = _reason(reason)
    row = _locked(record)
    _require_undecided(row)
    row.reason = reason
    _decided(row, staff, Status.REFUSED, timezone.now())
    row.save(update_fields=["reason", "status", "reviewed_by", "reviewed_at"])
    audit(staff, "verification.guarantor.refuse", row, reason=reason)
    record.refresh_from_db()
