"""Encryption of photos and sensitive fields, and keyed hashes for duplicate detection.

One key, FIELD_ENCRYPTION_KEY, protects everything here. Losing it makes the data unreadable.
"""

import hashlib
import hmac

from cryptography.fernet import Fernet
from django.conf import settings


def _fernet() -> Fernet:
    return Fernet(settings.FIELD_ENCRYPTION_KEY.encode())


def encrypt_bytes(data: bytes) -> bytes:
    return _fernet().encrypt(data)


def decrypt_bytes(token: bytes) -> bytes:
    return _fernet().decrypt(token)


def encrypt_text(value: str) -> str:
    """Encrypt a short text for a database column. An empty value stays empty."""
    return _fernet().encrypt(value.encode()).decode() if value else ""


def decrypt_text(token: str) -> str:
    return _fernet().decrypt(token.encode()).decode() if token else ""


def normalise_number(value: str) -> str:
    """Document and customer numbers compare without case, spaces or punctuation."""
    return "".join(ch for ch in value.upper() if ch.isalnum())


def keyed_hash(value: str) -> str:
    """A stable fingerprint of a number, useless without the key. Used to find duplicates."""
    key = hashlib.sha256(b"petitgombo-keyed-hash:" + settings.FIELD_ENCRYPTION_KEY.encode()).digest()
    return hmac.new(key, normalise_number(value).encode(), hashlib.sha256).hexdigest()
