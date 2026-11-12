"""Identity checks done by our own staff, until an identity provider is contracted."""

from .base import IdentityResult


class StaffReviewIdentity:
    """Hands every submission to a person. Nothing is approved automatically."""

    def start_verification(self, user_ref: str) -> str:
        return f"staff-review-{user_ref}"

    def get_result(self, session_ref: str) -> IdentityResult:
        return IdentityResult(status="human_review", full_name=None)

    def submit_documents(self, user_ref: str, front: bytes, back: bytes, selfie: bytes) -> IdentityResult:
        return IdentityResult(status="human_review", full_name=None)

    def match_selfie(self, user_ref: str, image: bytes) -> bool:
        # No automatic face match exists yet, so nothing is approved by accident.
        return False
