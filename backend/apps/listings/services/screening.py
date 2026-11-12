"""Signals that send an offer to a staff member before it is published."""

import re
import unicodedata

from django.conf import settings

from apps.listings.models import ModerationTerm, OfferCategory

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
# Eight or more digits, possibly separated by spaces, dots or dashes, with an optional leading "+".
PHONE = re.compile(r"\+?\d(?:[ .\-]?\d){7,}")


def normalise(text: str) -> str:
    """Lower case, no accents, single spaces: so that "Étranger" matches "etranger"."""
    decomposed = unicodedata.normalize("NFKD", text)
    unaccented = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return " ".join(unaccented.lower().split())


def _contact_details(note: str) -> bool:
    return bool(EMAIL.search(note) or PHONE.search(note))


def _terms_found(note: str) -> set[str]:
    haystack = f" {normalise(note)} "
    found = set()
    for term in ModerationTerm.objects.all():
        needle = normalise(term.text)
        if needle and re.search(rf"(?<!\w){re.escape(needle)}(?!\w)", haystack):
            found.add(term.kind)
    return found


def screen(*, category: OfferCategory, pay_xof: int, note: str, first_offer: bool) -> list[str]:
    """The flags for an offer, in a fixed order, each at most once."""
    flags = []
    if pay_xof > settings.OFFER_PAY_FLAG_FACTOR * category.suggested_pay_max:
        flags.append("pay_high")
    if pay_xof < category.suggested_pay_min:
        flags.append("pay_low")
    if _contact_details(note):
        flags.append("contact_details")
    found = _terms_found(note)
    for kind in ("appearance", "travel", "empty_home", "off_platform"):
        if kind in found:
            flags.append(kind)
    if first_offer:
        flags.append("first_offer")
    return flags
