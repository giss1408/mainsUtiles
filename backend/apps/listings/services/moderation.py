"""Staff decisions on offers. Every rule a decision must respect lives here."""

from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.listings.models import Offer
from apps.verification.services.tiers import householder_tier

PERMISSION = "listings.moderate_offer"


class ModerationError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _require(staff) -> None:
    if not (staff and staff.is_active and staff.is_staff and staff.has_perm(PERMISSION)):
        raise ModerationError("forbidden")


def _reason(value: str) -> str:
    value = (value or "").strip()
    if not value:
        raise ModerationError("reason_required")
    return value


@transaction.atomic
def publish(offer: Offer, *, staff) -> None:
    _require(staff)
    row = Offer.objects.select_for_update().get(pk=offer.pk)
    if row.status != Offer.Status.IN_REVIEW:
        raise ModerationError("invalid_state")
    if row.starts_at <= timezone.now():
        raise ModerationError("time_invalid")
    if householder_tier(row.author) != "H1":
        raise ModerationError("verification_required")
    now = timezone.now()
    row.status = Offer.Status.PUBLISHED
    row.published_at = now
    row.moderated_by = staff
    row.moderated_at = now
    row.save(update_fields=["status", "published_at", "moderated_by", "moderated_at", "updated_at"])
    audit(staff, "offer.publish", row)
    offer.refresh_from_db()


@transaction.atomic
def refuse(offer: Offer, *, staff, reason: str) -> None:
    _require(staff)
    reason = _reason(reason)
    row = Offer.objects.select_for_update().get(pk=offer.pk)
    if row.status != Offer.Status.IN_REVIEW:
        raise ModerationError("invalid_state")
    now = timezone.now()
    row.status = Offer.Status.REFUSED
    row.reason = reason
    row.moderated_by = staff
    row.moderated_at = now
    row.save(update_fields=["status", "reason", "moderated_by", "moderated_at", "updated_at"])
    audit(staff, "offer.refuse", row, reason=reason)
    offer.refresh_from_db()
