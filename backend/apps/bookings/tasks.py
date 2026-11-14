from celery import shared_task

from apps.bookings.services import applications, bookings, jobs, messages, reviews


@shared_task
def close_stale_applications() -> int:
    """Decline the pending applications of offers that were withdrawn, closed or have started."""
    return applications.close_stale()


@shared_task
def expire_unpaid_bookings() -> int:
    """Expire the bookings that were accepted but never paid, and reopen their offers."""
    return bookings.expire_unpaid()


@shared_task
def complete_overdue_bookings() -> int:
    """Complete the jobs the householder never confirmed, and owe the jobber."""
    return jobs.complete_overdue()


@shared_task
def close_no_show_bookings() -> int:
    """Cancel the paid bookings nobody attended and refund them."""
    return jobs.close_no_shows()


@shared_task
def flag_unclosed_bookings() -> int:
    """Hand the jobs that were never closed to staff."""
    return jobs.flag_unclosed()


@shared_task
def publish_due_reviews() -> int:
    """Publish the reviews whose window ended without the other side's."""
    return reviews.publish_due()


@shared_task
def queue_due_messages() -> int:
    """Queue the messages that time brings about: pay reminders and "the address is available"."""
    return messages.queue_due()
