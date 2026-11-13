import base64
import uuid

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class DeviceKey:
    """A device identity as the app would hold it: an id and an Ed25519 key pair."""

    def __init__(self):
        self.device_id = str(uuid.uuid4())
        self._private = Ed25519PrivateKey.generate()
        raw = self._private.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw
        )
        self.public_key = base64.b64encode(raw).decode()

    def sign(self, message: str) -> str:
        return base64.b64encode(self._private.sign(message.encode())).decode()


def confirm_contact_and_briefing(user, staff):
    """Take a jobber through the two steps that need no review: one confirmed contact, the briefing."""
    from apps.verification.models import BriefingCard
    from apps.verification.services import briefing, contacts

    contact = contacts.add_contact(user, name="Awa Koné", phone="01 01 01 01 01", relationship="parent")
    contacts.confirm_contact(user, contact.pk, contacts.send_code(contact, staff=staff))
    for card in briefing.briefing_cards(user):
        correct = BriefingCard.objects.get(pk=card["id"]).correct_index
        briefing.answer_card(user, card["id"], correct)


def make_offer(author, status="published", days=2, **overrides):
    """An offer of a verified householder; `days` ahead of today, 09:00 in Abidjan."""
    from datetime import UTC, datetime, timedelta
    from zoneinfo import ZoneInfo

    from django.utils import timezone

    from apps.listings.models import Offer, OfferCategory

    abidjan = ZoneInfo("Africa/Abidjan")
    today = datetime.now(abidjan).date()
    start = datetime(today.year, today.month, today.day, 9, tzinfo=abidjan) + timedelta(days=days)
    values = {
        "author": author,
        "category": OfferCategory.objects.get(name="Ménage"),
        "category_name": "Ménage",
        "duties": ["Dépoussiérer"],
        "starts_at": start.astimezone(UTC),
        "duration_minutes": 180,
        "pay_xof": 3000,
        "note": "Merci d'apporter des gants.",
        "commune": "Cocody",
        "quartier": "Angré",
        "status": status,
        "sent_at": timezone.now(),
        "published_at": timezone.now() if status == "published" else None,
    }
    values.update(overrides)
    return Offer.objects.create(**values)


def j1_jobber(jpeg, verifier):
    """A jobber with all four steps confirmed."""
    from tests.test_jobber_tier import verified_jobber

    return verified_jobber(jpeg, verifier)[0]
