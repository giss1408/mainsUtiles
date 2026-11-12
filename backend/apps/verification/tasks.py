from celery import shared_task
from django.db import transaction
from django.utils import timezone

from apps.verification.models import AddressProof, HomeLocation, Status


@shared_task
def expire_address_proofs() -> int:
    """Expire confirmed proofs of address past their date, with the home position they backed."""
    with transaction.atomic():
        due = list(
            AddressProof.objects.select_for_update()
            .filter(status=Status.CONFIRMED, expires_at__lte=timezone.now())
            .values_list("pk", "user_id")
        )
        AddressProof.objects.filter(pk__in=[pk for pk, _ in due]).update(status=Status.EXPIRED)
        HomeLocation.objects.filter(user_id__in=[user for _, user in due], status=Status.CONFIRMED).update(
            status=Status.EXPIRED
        )
    return len(due)
