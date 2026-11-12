"""Device enrolment: a user applies, staff approve and send a confirmation number, the user confirms.

All rules live here. Views, the web console and the staff API only call these functions.
"""

import hashlib
import hmac
import secrets
from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Device, DeviceEnrolmentRequest, User
from apps.accounts.phones import InvalidPhone, normalise
from apps.audit.services import record

Status = DeviceEnrolmentRequest.Status
Kind = DeviceEnrolmentRequest.Kind

CONFIRMATION_MESSAGE = (
    "petitGombo : votre numéro de confirmation est {code}. Saisissez-le dans l'application. "
    "Ne le partagez avec personne : notre équipe ne vous le demandera jamais."
)

FLAG_DEVICE_MULTIPLE_NUMBERS = "device_multiple_numbers"

_ALLOWED = {
    "approve": (Status.PENDING, Status.HELD),
    "refuse": (Status.PENDING, Status.HELD),
    "hold": (Status.PENDING,),
    "issue_code": (Status.APPROVED, Status.CODE_SENT),
}


class EnrolmentError(Exception):
    """Raised with a stable `code` that callers map to a message and an HTTP status."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _hash_token(client_token: str) -> str:
    return hashlib.sha256(client_token.encode()).hexdigest()


def _hash_code(request_id, code: str) -> str:
    return hmac.new(settings.SECRET_KEY.encode(), f"{request_id}:{code}".encode(), hashlib.sha256).hexdigest()


def _round_coordinate(value) -> Decimal | None:
    if value is None:
        return None
    return Decimal(str(value)).quantize(Decimal("0.01"))


def check_client_token(req: DeviceEnrolmentRequest, client_token: str) -> bool:
    return hmac.compare_digest(req.client_token_hash, _hash_token(client_token or ""))


def _check_rate_limits(phone: str, device_id: UUID, ip: str | None) -> None:
    recent = DeviceEnrolmentRequest.objects.filter(created_at__gte=timezone.now() - timedelta(hours=24))
    limits = [
        (recent.filter(phone=phone), settings.ENROLMENT_MAX_PER_PHONE_PER_DAY),
        (recent.filter(device_id=device_id), settings.ENROLMENT_MAX_PER_DEVICE_PER_DAY),
    ]
    if ip:
        limits.append((recent.filter(ip_address=ip), settings.ENROLMENT_MAX_PER_IP_PER_DAY))
    for queryset, maximum in limits:
        if queryset.count() >= maximum:
            raise EnrolmentError("rate_limited")


def apply(
    *,
    phone: str,
    role: str,
    device_id: UUID,
    device_model: str,
    platform: str,
    public_key: str,
    client_token: str,
    ip: str | None = None,
    approx_lat=None,
    approx_lng=None,
) -> DeviceEnrolmentRequest:
    """Create an application, or return the open one this device already made for this number."""
    try:
        phone = normalise(phone)
    except InvalidPhone as exc:
        raise EnrolmentError("invalid_phone") from exc

    token_hash = _hash_token(client_token)
    existing = DeviceEnrolmentRequest.objects.filter(
        device_id=device_id,
        phone=phone,
        role=role,
        client_token_hash=token_hash,
        status__in=DeviceEnrolmentRequest.OPEN_STATUSES,
    ).first()
    if existing:
        return existing

    _check_rate_limits(phone, device_id, ip)

    flags = []
    if DeviceEnrolmentRequest.objects.filter(device_id=device_id).exclude(phone=phone).exists():
        flags.append(FLAG_DEVICE_MULTIPLE_NUMBERS)

    has_account = User.objects.filter(phone=phone, role=role, is_active=True).exists()
    return DeviceEnrolmentRequest.objects.create(
        phone=phone,
        role=role,
        kind=Kind.NEW_DEVICE if has_account else Kind.NEW_ACCOUNT,
        device_id=device_id,
        device_model=device_model,
        platform=platform,
        public_key=public_key,
        client_token_hash=token_hash,
        ip_address=ip,
        approx_lat=_round_coordinate(approx_lat),
        approx_lng=_round_coordinate(approx_lng),
        flags=flags,
    )


def _locked(req: DeviceEnrolmentRequest) -> DeviceEnrolmentRequest:
    """Re-read the row under a lock so two staff members cannot act on the same state."""
    return DeviceEnrolmentRequest.objects.select_for_update().get(pk=req.pk)


def _require(staff, permission: str) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(permission)):
        raise EnrolmentError("forbidden")


def _require_state(row: DeviceEnrolmentRequest, action: str) -> None:
    if row.status not in _ALLOWED[action]:
        raise EnrolmentError("invalid_state")


@transaction.atomic
def approve(req: DeviceEnrolmentRequest, *, staff) -> None:
    _require(staff, "accounts.review_enrolment")
    row = _locked(req)
    _require_state(row, "approve")
    if row.kind == Kind.NEW_DEVICE and row.selfie_verified_at is None:
        raise EnrolmentError("selfie_required")
    row.status = Status.APPROVED
    row.approved_by = staff
    row.approved_at = timezone.now()
    row.save(update_fields=["status", "approved_by", "approved_at"])
    record(staff, "enrolment.approve", row)
    req.refresh_from_db()


@transaction.atomic
def refuse(req: DeviceEnrolmentRequest, *, staff, reason: str) -> None:
    _require(staff, "accounts.review_enrolment")
    row = _locked(req)
    _require_state(row, "refuse")
    row.status = Status.REFUSED
    row.reason = reason
    row.save(update_fields=["status", "reason"])
    record(staff, "enrolment.refuse", row, reason=reason)
    req.refresh_from_db()


@transaction.atomic
def hold(req: DeviceEnrolmentRequest, *, staff, reason: str) -> None:
    _require(staff, "accounts.review_enrolment")
    row = _locked(req)
    _require_state(row, "hold")
    row.status = Status.HELD
    row.reason = reason
    row.save(update_fields=["status", "reason"])
    record(staff, "enrolment.hold", row, reason=reason)
    req.refresh_from_db()


@transaction.atomic
def issue_code(req: DeviceEnrolmentRequest, *, staff) -> str:
    """Generate a new confirmation number and return it once. Only its hash is stored."""
    _require(staff, "accounts.send_enrolment_code")
    row = _locked(req)
    _require_state(row, "issue_code")
    code = f"{secrets.randbelow(10**6):06d}"
    row.previous_code_hash = row.code_hash
    row.code_hash = _hash_code(row.pk, code)
    row.code_attempts = 0
    row.code_expires_at = timezone.now() + timedelta(minutes=settings.ENROLMENT_CODE_TTL_MINUTES)
    row.status = Status.CODE_SENT
    row.sent_by = staff
    row.sent_at = timezone.now()
    row.save(
        update_fields=[
            "previous_code_hash",
            "code_hash",
            "code_attempts",
            "code_expires_at",
            "status",
            "sent_by",
            "sent_at",
        ]
    )
    record(staff, "enrolment.send_code", row)
    req.refresh_from_db()
    return code


def _bind_device(row: DeviceEnrolmentRequest) -> Device:
    user, _ = User.objects.get_or_create(phone=row.phone, role=row.role)
    existing = Device.objects.filter(pk=row.device_id).first()
    if existing and existing.user_id != user.pk:
        raise EnrolmentError("invalid_state")
    now = timezone.now()
    user.devices.filter(status=Device.Status.ACTIVE).exclude(pk=row.device_id).update(
        status=Device.Status.REVOKED, revoked_at=now
    )
    if existing:
        existing.public_key = row.public_key
        existing.model = row.device_model
        existing.platform = row.platform
        existing.status = Device.Status.ACTIVE
        existing.revoked_at = None
        existing.save()
        return existing
    return Device.objects.create(
        id=row.device_id,
        user=user,
        public_key=row.public_key,
        model=row.device_model,
        platform=row.platform,
    )


def confirm(req: DeviceEnrolmentRequest, *, client_token: str, code: str) -> Device:
    """Check the confirmation number and bind the device. Safe to repeat after success."""
    if not check_client_token(req, client_token):
        raise EnrolmentError("forbidden")

    # Failed attempts must be saved even though the call ends in an error,
    # so the error is raised after the transaction commits.
    error = None
    device = None
    with transaction.atomic():
        row = _locked(req)
        submitted = _hash_code(row.pk, code or "")
        matches = bool(row.code_hash) and hmac.compare_digest(row.code_hash, submitted)

        if row.status == Status.COMPLETED:
            if matches:
                device = Device.objects.get(pk=row.device_id)
            else:
                error = "code_invalid"
        elif row.status == Status.LOCKED:
            error = "locked"
        elif row.status != Status.CODE_SENT:
            error = "invalid_state"
        elif row.previous_code_hash and hmac.compare_digest(row.previous_code_hash, submitted):
            error = "code_replaced"
        elif row.code_expires_at is None or timezone.now() > row.code_expires_at:
            error = "code_expired"
        elif not matches:
            row.code_attempts += 1
            if row.code_attempts >= settings.ENROLMENT_CODE_MAX_ATTEMPTS:
                row.status = Status.LOCKED
                error = "locked"
            else:
                error = "code_invalid"
            row.save(update_fields=["code_attempts", "status"])
        else:
            device = _bind_device(row)
            row.status = Status.COMPLETED
            row.completed_at = timezone.now()
            row.save(update_fields=["status", "completed_at"])

    req.refresh_from_db()
    if error:
        raise EnrolmentError(error)
    return device
