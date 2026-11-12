from apps.listings.models import OfferCategory


def active_categories():
    """The categories a householder may choose for a new offer."""
    return OfferCategory.objects.filter(active=True)
