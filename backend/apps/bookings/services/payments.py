"""Payment for a booking. The platform has no payment API: householders pay a receiving number of
the platform, send proof, and staff check it against the platform account's real history. Every
rule lives here; views only translate HTTP."""

from apps.bookings.models import PaymentMethod


def available() -> bool:
    """The service is provided only while at least one method is active with a number."""
    return PaymentMethod.objects.available().exists()


def instructions() -> list[dict]:
    """What a householder is told about where to pay. The platform's numbers are not secret."""
    return [
        {
            "id": method.pk,
            "provider": method.provider,
            "provider_label": method.get_provider_display(),
            "number": method.number,
            "account_name": method.account_name,
        }
        for method in PaymentMethod.objects.available()
    ]
