from celery import shared_task

from apps.verification.services import contacts
from apps.verification.services.submissions import expire_guarantors as sweep_guarantors
from apps.verification.services.submissions import expire_overdue


@shared_task
def expire_address_proofs() -> int:
    """Expire confirmed proofs of address past their date, with the home position they backed."""
    return expire_overdue()


@shared_task
def expire_guarantors() -> int:
    """Expire confirmed guarantors past their date."""
    return sweep_guarantors()


@shared_task
def apply_contact_replacements() -> int:
    """Retire trusted contacts whose replacement has confirmed, been noticed and waited."""
    return contacts.apply_replacements()
