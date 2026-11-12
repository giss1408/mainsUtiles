"""Development and test stand-ins. They never contact an external service."""

from urllib.parse import quote

from .base import IdentityResult, MessageResult, PaymentResult


class MockMessaging:
    outbox: list[tuple[str, str]] = []

    def whatsapp_link(self, phone_e164: str, text: str) -> str:
        return f"https://wa.me/{phone_e164.lstrip('+')}?text={quote(text, safe='')}"

    def send_sms(self, phone_e164: str, text: str) -> MessageResult:
        self.outbox.append((phone_e164, text))
        return MessageResult(provider_ref=f"mock-sms-{len(self.outbox)}", accepted=True)


class MockPayment:
    def collect(self, reference: str, phone_e164: str, amount_xof: int) -> PaymentResult:
        return PaymentResult(provider_ref=f"mock-collect-{reference}", status="pending")

    def payout(self, reference: str, phone_e164: str, amount_xof: int) -> PaymentResult:
        return PaymentResult(provider_ref=f"mock-payout-{reference}", status="pending")

    def refund(self, reference: str) -> PaymentResult:
        return PaymentResult(provider_ref=f"mock-refund-{reference}", status="pending")

    def verify_webhook(self, headers: dict, body: bytes) -> bool:
        return headers.get("X-Mock-Signature") == "valid"


class MockIdentity:
    def start_verification(self, user_ref: str) -> str:
        return f"mock-session-{user_ref}"

    def get_result(self, session_ref: str) -> IdentityResult:
        return IdentityResult(status="pending", full_name=None)

    def submit_documents(self, user_ref: str, front: bytes, back: bytes, selfie: bytes) -> IdentityResult:
        return IdentityResult(status="pending", full_name=None)

    def match_selfie(self, user_ref: str, image: bytes) -> bool:
        # The mock never confirms a face, so nothing is approved by accident.
        return False


class MockMap:
    def static_area_image_url(self, lat: float, lng: float, radius_m: int) -> str:
        return f"https://maps.invalid/static?lat={lat:.3f}&lng={lng:.3f}&r={radius_m}"
