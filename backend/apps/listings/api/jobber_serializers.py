from rest_framework import serializers

from apps.listings.models import Offer


class PublicOfferSerializer(serializers.ModelSerializer):
    """What a jobber may see of an offer. No author, flags, reason or any position."""

    class Meta:
        model = Offer
        fields = [
            "id",
            "category_name",
            "duties",
            "starts_at",
            "duration_minutes",
            "pay_xof",
            "note",
            "commune",
            "quartier",
        ]
        read_only_fields = fields
