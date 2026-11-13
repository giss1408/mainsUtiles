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
