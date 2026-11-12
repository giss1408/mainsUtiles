"""Staff sign-in: a password and a phone that an administrator has activated."""

from uuid import UUID

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.cache import cache
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Device, Role, User
from apps.audit.services import record

from .device_auth import AuthError, TokenPair, consume_challenge, issue_tokens, verify_signature

__all__ = ["AuthError", "activate_device", "login", "register_device", "revoke_device"]


def _failures_key(username: str) -> str:
    return f"staff-login-failures:{username.strip().lower()}"


def _check_password(username: str, password: str) -> User:
    """Return the staff member, or fail the same way for a wrong name and a wrong password."""
    key = _failures_key(username)
    if cache.get(key, 0) >= settings.STAFF_LOGIN_MAX_FAILURES:
        raise AuthError("locked")
    user = authenticate(username=username, password=password)
    if user is None or user.role != Role.STAFF or not user.is_staff:
        lock_seconds = settings.STAFF_LOGIN_LOCK_MINUTES * 60
        cache.add(key, 0, timeout=lock_seconds)
        if cache.incr(key) >= settings.STAFF_LOGIN_MAX_FAILURES:
            cache.touch(key, lock_seconds)
        raise AuthError("bad_credentials")
    return user


def register_device(
    *, username: str, password: str, device_id: UUID, device_model: str, platform: str, public_key: str
) -> Device:
    """Record a staff phone as pending. A phone already known is returned unchanged."""
    user = _check_password(username, password)
    device, _ = Device.objects.get_or_create(
        pk=device_id,
        defaults={
            "user": user,
            "public_key": public_key,
            "model": device_model,
            "platform": platform,
            "status": Device.Status.PENDING,
        },
    )
    if device.user_id != user.pk:
        raise AuthError("bad_credentials")
    return device


def _require_superuser(admin) -> None:
    if not (admin and admin.is_active and admin.is_superuser):
        raise PermissionDenied


def _locked_staff_device(device: Device) -> Device:
    row = Device.objects.select_for_update().select_related("user").get(pk=device.pk)
    if row.user.role != Role.STAFF:
        raise AuthError("invalid_state")
    return row


@transaction.atomic
def activate_device(device: Device, *, admin) -> None:
    """Make a pending staff phone the staff member's only active one."""
    _require_superuser(admin)
    row = _locked_staff_device(device)
    if row.status != Device.Status.PENDING:
        raise AuthError("invalid_state")
    Device.objects.filter(user=row.user, status=Device.Status.ACTIVE).update(
        status=Device.Status.REVOKED, revoked_at=timezone.now()
    )
    row.status = Device.Status.ACTIVE
    row.save(update_fields=["status"])
    record(admin, "staff_device.activate", row)
    device.refresh_from_db()


@transaction.atomic
def revoke_device(device: Device, *, admin) -> None:
    _require_superuser(admin)
    row = _locked_staff_device(device)
    if row.status == Device.Status.REVOKED:
        raise AuthError("invalid_state")
    row.status = Device.Status.REVOKED
    row.revoked_at = timezone.now()
    row.save(update_fields=["status", "revoked_at"])
    record(admin, "staff_device.revoke", row)
    device.refresh_from_db()


def login(*, username: str, password: str, device_id: UUID, nonce: str, signature_b64: str) -> TokenPair:
    user = _check_password(username, password)
    device = Device.objects.select_related("user").filter(pk=device_id, user=user).first()
    if device is None:
        raise AuthError("unknown_device")
    if device.status == Device.Status.PENDING:
        raise AuthError("device_pending")
    if device.status != Device.Status.ACTIVE:
        raise AuthError("device_revoked")
    consume_challenge(device_id, nonce)
    verify_signature(device, nonce, signature_b64)
    cache.delete(_failures_key(username))
    return issue_tokens(device)
