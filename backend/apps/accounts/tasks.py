from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.utils import timezone

from apps.accounts.models import DeviceEnrolmentRequest


@shared_task
def expire_stale_enrolments() -> int:
    """Close applications that stayed open longer than the configured number of days."""
    cutoff = timezone.now() - timedelta(days=settings.ENROLMENT_APPLICATION_TTL_DAYS)
    return DeviceEnrolmentRequest.objects.filter(
        status__in=DeviceEnrolmentRequest.OPEN_STATUSES, created_at__lt=cutoff
    ).update(status=DeviceEnrolmentRequest.Status.EXPIRED)
