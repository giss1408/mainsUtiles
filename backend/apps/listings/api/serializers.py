from django.conf import settings
from rest_framework import serializers

from apps.listings.models import Offer, OfferCategory


class OfferDraftSerializer(serializers.Serializer):
    """The fields a householder sends for a draft. Every rule is checked by the service."""

    category_id = serializers.IntegerField(min_value=1)
    duties = serializers.ListField(child=serializers.CharField(max_length=120), allow_empty=True)
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    pay_xof = serializers.IntegerField()
    note = serializers.CharField(allow_blank=True, default="", max_length=2000, trim_whitespace=False)


class OfferPatchSerializer(OfferDraftSerializer):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.required = False


class MyOfferSerializer(serializers.ModelSerializer):
    """What the author sees of their own offer. Never the screening flags: they stay internal."""

    category_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = Offer
        fields = [
            "id",
            "category_id",
            "category_name",
            "duties",
            "starts_at",
            "duration_minutes",
            "pay_xof",
            "note",
            "commune",
            "quartier",
            "status",
            "reason",
            "created_at",
        ]
        read_only_fields = fields


class OfferCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = OfferCategory
        fields = ["id", "name", "duties", "durations_minutes", "suggested_pay_min", "suggested_pay_max"]
        read_only_fields = fields


def offer_limits() -> dict:
    return {
        "earliest_start": settings.OFFER_EARLIEST_START,
        "latest_end": settings.OFFER_LATEST_END,
        "min_pay": settings.OFFER_MIN_PAY_XOF,
        "max_pay": settings.OFFER_MAX_PAY_XOF,
        "max_days_ahead": settings.OFFER_MAX_DAYS_AHEAD,
        "note_max_length": settings.OFFER_NOTE_MAX_LENGTH,
    }
