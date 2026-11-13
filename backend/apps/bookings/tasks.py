from celery import shared_task

from apps.bookings.services import applications


@shared_task
def close_stale_applications() -> int:
    """Decline the pending applications of offers that were withdrawn, closed or have started."""
    return applications.close_stale()
