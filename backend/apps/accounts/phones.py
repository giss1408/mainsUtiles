"""Phone number normalisation. Numbers are stored in E.164."""

import phonenumbers
from django.conf import settings


class InvalidPhone(ValueError):
    pass


def normalise(raw: str) -> str:
    """Return the E.164 form of a number typed in local or international format."""
    regions = settings.ALLOWED_PHONE_REGIONS
    try:
        parsed = phonenumbers.parse(raw or "", regions[0])
    except phonenumbers.NumberParseException as exc:
        raise InvalidPhone(raw) from exc
    if not phonenumbers.is_valid_number(parsed):
        raise InvalidPhone(raw)
    if phonenumbers.region_code_for_number(parsed) not in regions:
        raise InvalidPhone(raw)
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
