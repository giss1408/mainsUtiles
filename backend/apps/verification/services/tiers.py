"""The householder's tier and the checklist shown in the app. Both are computed, never stored."""

from django.conf import settings
from django.utils import timezone

from apps.verification.models import OPEN, AddressProof, HomeLocation, IdentityVerification, Status


def current_record(model, user):
    """The record that counts for this step: the open one if any (there is at most one),
    otherwise the most recent closed one."""
    records = model.objects.filter(user=user)
    return records.filter(status__in=OPEN).first() or records.order_by("-created_at").first()


def _status(record) -> str:
    if record is None:
        return "not_started"
    expires_at = getattr(record, "expires_at", None)
    if record.status == Status.CONFIRMED and expires_at and expires_at <= timezone.now():
        # Past its date but not yet swept by the periodic task.
        return Status.EXPIRED.value
    return record.status


def _step(record) -> dict:
    status = _status(record)
    return {"status": status, "reason": record.reason if status == Status.REFUSED else ""}


def householder_tier(user) -> str:
    """H1 when identity, proof of address and home position are all confirmed; H0 otherwise."""
    if user.role != "householder":
        return "H0"
    records = [current_record(model, user) for model in (IdentityVerification, AddressProof, HomeLocation)]
    return "H1" if all(_status(record) == Status.CONFIRMED for record in records) else "H0"


def checklist(user) -> dict:
    """Statuses only. Never the recorded identity fields, photos or coordinates."""
    address = current_record(AddressProof, user)
    address_status = _status(address)
    return {
        "tier": householder_tier(user),
        "review_hours": settings.VERIFICATION_REVIEW_HOURS,
        "communes": list(settings.SERVICE_COMMUNES),
        "identity": _step(current_record(IdentityVerification, user)),
        "address": {
            **_step(address),
            "commune": address.commune if address else "",
            "quartier": address.quartier if address else "",
            "expires_at": (
                address.expires_at.isoformat()
                if address and address.expires_at and address_status == Status.CONFIRMED
                else None
            ),
        },
        "home_location": _step(current_record(HomeLocation, user)),
    }
