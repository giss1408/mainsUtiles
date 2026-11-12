from celery import shared_task

from apps.verification.services.submissions import expire_overdue


@shared_task
def expire_address_proofs() -> int:
    """Expire confirmed proofs of address past their date, with the home position they backed."""
    return expire_overdue()
