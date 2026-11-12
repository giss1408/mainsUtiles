"""Interfaces for every external service. Real providers implement these; code depends only on them."""

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class MessageResult:
    provider_ref: str
    accepted: bool


@dataclass(frozen=True)
class PaymentResult:
    provider_ref: str
    status: str  # pending | successful | failed


@dataclass(frozen=True)
class IdentityResult:
    status: str  # pending | verified | action_required
    full_name: str | None


class MessagingProvider(Protocol):
    def whatsapp_link(self, phone_e164: str, text: str) -> str: ...

    def send_sms(self, phone_e164: str, text: str) -> MessageResult: ...


class PaymentProvider(Protocol):
    def collect(self, reference: str, phone_e164: str, amount_xof: int) -> PaymentResult: ...

    def payout(self, reference: str, phone_e164: str, amount_xof: int) -> PaymentResult: ...

    def refund(self, reference: str) -> PaymentResult: ...

    def verify_webhook(self, headers: dict, body: bytes) -> bool: ...


class IdentityProvider(Protocol):
    def start_verification(self, user_ref: str) -> str: ...

    def get_result(self, session_ref: str) -> IdentityResult: ...

    def match_selfie(self, user_ref: str, image: bytes) -> bool: ...


class MapProvider(Protocol):
    def static_area_image_url(self, lat: float, lng: float, radius_m: int) -> str: ...
