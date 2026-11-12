"""What a householder sends for verification: photos, a proof of address, a home position."""

import hashlib
import uuid
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

from django.conf import settings
from django.db import IntegrityError, transaction

from apps.providers import registry
from apps.verification.models import (
    OPEN,
    UNDECIDED,
    AddressProof,
    HomeLocation,
    IdentityVerification,
    Status,
    VerificationPhoto,
)

from .encryption import decrypt_bytes, decrypt_text, encrypt_bytes, encrypt_text

JPEG_MAGIC = b"\xff\xd8\xff"
FLAG_PHOTO_REUSED = "photo_reused"
REPLACED_REASON = "Remplacée"

Position = tuple[float, float]


class VerificationError(Exception):
    """A rule was broken. `code` is mapped to a status and a French message by the callers."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _require_householder(user) -> None:
    if not (user and user.is_active and user.role == "householder"):
        raise VerificationError("forbidden")


def _path(storage_name: str) -> Path:
    return Path(settings.VERIFICATION_STORAGE_DIR) / storage_name


def store_photo(
    user, kind: str, data: bytes, captured_at: datetime, position: Position | None
) -> VerificationPhoto:
    """Check the image and write it encrypted. The plain image never touches the disk."""
    if not data or not data.startswith(JPEG_MAGIC):
        raise VerificationError("photo_invalid")
    if len(data) > settings.VERIFICATION_PHOTO_MAX_BYTES:
        raise VerificationError("photo_too_large")
    storage_name = f"{uuid.uuid4()}.bin"
    path = _path(storage_name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encrypt_bytes(data))
    return VerificationPhoto.objects.create(
        owner=user,
        kind=kind,
        storage_name=storage_name,
        sha256=hashlib.sha256(data).hexdigest(),
        captured_at=captured_at,
        capture_position=encrypt_text(f"{position[0]},{position[1]}") if position else "",
    )


def read_photo_bytes(photo: VerificationPhoto) -> bytes:
    return decrypt_bytes(_path(photo.storage_name).read_bytes())


@contextmanager
def _submission():
    """One transaction for a whole submission; files written before a failure are removed."""
    names: list[str] = []
    try:
        with transaction.atomic():
            yield names
    except IntegrityError as exc:
        _remove(names)
        # Two submissions of the same step raced: the database kept only the first.
        raise VerificationError("invalid_state") from exc
    except BaseException:
        _remove(names)
        raise


def _remove(storage_names: list[str]) -> None:
    for name in storage_names:
        _path(name).unlink(missing_ok=True)


def _reused(user, photos: list[VerificationPhoto]) -> list[str]:
    seen_elsewhere = (
        VerificationPhoto.objects.filter(sha256__in=[p.sha256 for p in photos]).exclude(owner=user).exists()
    )
    return [FLAG_PHOTO_REUSED] if seen_elsewhere else []


def _require_no_open(model, user) -> None:
    if model.objects.filter(user=user, status__in=OPEN).exists():
        raise VerificationError("invalid_state")


def submit_identity(
    user,
    *,
    document_type: str,
    front: bytes,
    back: bytes,
    selfie: bytes,
    captured_at: datetime,
    position: Position | None = None,
) -> IdentityVerification:
    _require_householder(user)
    if document_type not in settings.IDENTITY_DOCUMENT_TYPES:
        raise VerificationError("document_type_invalid")
    _require_no_open(IdentityVerification, user)
    with _submission() as written:
        photos = []
        for kind, data in (("id_front", front), ("id_back", back), ("selfie", selfie)):
            photo = store_photo(user, kind, data, captured_at, position)
            written.append(photo.storage_name)
            photos.append(photo)
        record = IdentityVerification.objects.create(
            user=user,
            front=photos[0],
            back=photos[1],
            selfie=photos[2],
            document_type=document_type,
            flags=_reused(user, photos),
        )
    # With staff review this only announces the submission; a real provider would start its checks.
    registry.get_identity().submit_documents(str(user.pk), front, back, selfie)
    return record


def submit_address_proof(
    user,
    *,
    document_type: str,
    photo: bytes,
    commune: str,
    quartier: str,
    captured_at: datetime,
    position: Position | None = None,
) -> AddressProof:
    _require_householder(user)
    if document_type not in settings.ADDRESS_PROOF_TYPES:
        raise VerificationError("document_type_invalid")
    if commune not in settings.SERVICE_COMMUNES:
        raise VerificationError("commune_invalid")
    quartier = (quartier or "").strip()
    if not quartier:
        raise VerificationError("quartier_required")
    _require_no_open(AddressProof, user)
    with _submission() as written:
        stored = store_photo(user, "address_proof", photo, captured_at, position)
        written.append(stored.storage_name)
        return AddressProof.objects.create(
            user=user,
            photo=stored,
            document_type=document_type,
            commune=commune,
            quartier=quartier[:80],
            flags=_reused(user, [stored]),
        )


def record_home_location(
    user, *, lat: float, lng: float, accuracy_m: float, mock_location: bool, captured_at: datetime
) -> HomeLocation:
    _require_householder(user)
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or accuracy_m < 0:
        raise VerificationError("location_inaccurate")
    if accuracy_m > settings.HOME_PIN_MAX_ACCURACY_M:
        raise VerificationError("location_inaccurate")
    with _submission():
        # Once the address is confirmed the position it was judged against is final.
        confirmed = AddressProof.objects.filter(user=user, status=Status.CONFIRMED).exists()
        if confirmed or HomeLocation.objects.filter(user=user, status=Status.CONFIRMED).exists():
            raise VerificationError("invalid_state")
        HomeLocation.objects.filter(user=user, status__in=UNDECIDED).update(
            status=Status.REFUSED, reason=REPLACED_REASON
        )
        return HomeLocation.objects.create(
            user=user,
            latitude=encrypt_text(repr(float(lat))),
            longitude=encrypt_text(repr(float(lng))),
            accuracy_m=round(accuracy_m),
            mock_location=bool(mock_location),
            captured_at=captured_at,
        )


def location_coordinates(location: HomeLocation) -> Position:
    """Decrypted coordinates. For the staff review page only."""
    return float(decrypt_text(location.latitude)), float(decrypt_text(location.longitude))
