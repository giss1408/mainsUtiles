from celery import shared_task

from apps.listings.services import offers


@shared_task
def tidy_offers() -> dict:
    """Close offers whose start has passed and withdraw those of householders who lost verification."""
    return offers.tidy()
