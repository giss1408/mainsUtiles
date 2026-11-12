"""Sign-in with the key held by an enrolled device, and the tokens that follow."""

import base64
import binascii
import hashlib
import secrets
from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

import jwt
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import Device, RefreshToken

JWT_ALGORITHM = "HS256"


@dataclass(frozen=True)
class TokenPair:
    access: str
    refresh: str


class AuthError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _challenge_key(device_id) -> str:
    return f"auth-challenge:{device_id}"


def signed_message(device_id, nonce: str) -> bytes:
    return f"petitgombo-auth:{device_id}:{nonce}".encode()


def create_challenge(device_id: UUID) -> str:
    """Issue a single-use nonce. Issued for unknown devices too, so devices cannot be enumerated."""
    nonce = secrets.token_urlsafe(24)
    cache.set(_challenge_key(device_id), nonce, timeout=settings.AUTH_CHALLENGE_TTL_SECONDS)
    return nonce


def consume_challenge(device_id: UUID, nonce: str) -> None:
    key = _challenge_key(device_id)
    expected = cache.get(key)
    if not expected or not secrets.compare_digest(str(expected), str(nonce)):
        raise AuthError("challenge_invalid")
    cache.delete(key)


def verify_signature(device: Device, nonce: str, signature_b64: str) -> None:
    try:
        public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(device.public_key))
        public_key.verify(base64.b64decode(signature_b64, validate=True), signed_message(device.pk, nonce))
    except (InvalidSignature, binascii.Error, ValueError) as exc:
        raise AuthError("signature_invalid") from exc


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _lifetimes(device: Device) -> tuple[timedelta, timedelta]:
    if device.user.role == "staff":
        return (
            timedelta(minutes=settings.STAFF_ACCESS_TOKEN_TTL_MINUTES),
            timedelta(hours=settings.STAFF_REFRESH_TOKEN_TTL_HOURS),
        )
    return (
        timedelta(minutes=settings.ACCESS_TOKEN_TTL_MINUTES),
        timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS),
    )


def issue_tokens(device: Device) -> TokenPair:
    access_ttl, refresh_ttl = _lifetimes(device)
    now = timezone.now()
    access = jwt.encode(
        {
            "sub": str(device.user_id),
            "did": str(device.pk),
            "role": device.user.role,
            "iat": now,
            "exp": now + access_ttl,
        },
        settings.SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )
    refresh = secrets.token_urlsafe(32)
    RefreshToken.objects.create(device=device, token_hash=_hash(refresh), expires_at=now + refresh_ttl)
    return TokenPair(access=access, refresh=refresh)


def active_device(device_id: UUID) -> Device:
    device = Device.objects.select_related("user").filter(pk=device_id).first()
    if device is None:
        raise AuthError("unknown_device")
    if device.status != Device.Status.ACTIVE or not device.user.is_active:
        raise AuthError("device_revoked")
    return device


def sign_in(device_id: UUID, nonce: str, signature_b64: str) -> TokenPair:
    consume_challenge(device_id, nonce)
    device = active_device(device_id)
    if device.user.role == "staff":
        # Staff must also give their password: see staff_auth.login.
        raise AuthError("unknown_device")
    verify_signature(device, nonce, signature_b64)
    return issue_tokens(device)


def rotate(refresh: str) -> TokenPair:
    """Exchange a refresh token for a new pair. A token presented twice revokes the device's tokens."""
    replayed = False
    with transaction.atomic():
        token = (
            RefreshToken.objects.select_for_update()
            .select_related("device__user")
            .filter(token_hash=_hash(refresh or ""))
            .first()
        )
        if token is None:
            raise AuthError("refresh_invalid")
        now = timezone.now()
        device = token.device
        if token.rotated_at is not None:
            RefreshToken.objects.filter(device=device, revoked_at__isnull=True).update(revoked_at=now)
            replayed = True
        elif (
            token.revoked_at is not None
            or token.expires_at <= now
            or device.status != Device.Status.ACTIVE
            or not device.user.is_active
        ):
            raise AuthError("refresh_invalid")
        else:
            token.rotated_at = now
            token.revoked_at = now
            token.save(update_fields=["rotated_at", "revoked_at"])
            pair = issue_tokens(device)
    if replayed:
        raise AuthError("refresh_invalid")
    return pair


def decode_access(token: str) -> dict:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[JWT_ALGORITHM])
