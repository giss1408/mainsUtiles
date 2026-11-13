from celery import shared_task

from apps.bookings.services import applications, bookings


@shared_task
def close_stale_applications() -> int:
    """Decline the pending applications of offers that were withdrawn, closed or have started."""
    return applications.close_stale()


@shared_task
def expire_unpaid_bookings() -> int:
    """Expire the bookings that were accepted but never paid, and reopen their offers."""
    return bookings.expire_unpaid()
