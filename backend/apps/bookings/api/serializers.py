from rest_framework import serializers


class ApplyBodySerializer(serializers.Serializer):
    # The length limit (APPLICATION_MESSAGE_MAX) is enforced by the service, which answers with a
    # French message; the schema does not repeat it.
    message = serializers.CharField(required=False, allow_blank=True, default="")


class OfferLineSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    pay_xof = serializers.IntegerField()
    commune = serializers.CharField()
    quartier = serializers.CharField()
    status = serializers.CharField()


class BookingRefSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()


class ApplicationSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    offer_id = serializers.UUIDField()
    status = serializers.CharField()
    created_at = serializers.DateTimeField()


class ApplicationItemSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    message = serializers.CharField()
    created_at = serializers.DateTimeField()
    offer = OfferLineSerializer()
    booking = BookingRefSerializer(allow_null=True)


class JobberBookingSerializer(serializers.Serializer):
    """A booking as its jobber sees it. Never an address and never the householder."""

    id = serializers.UUIDField()
    status = serializers.CharField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    pay_xof = serializers.IntegerField()
    commune = serializers.CharField()
    quartier = serializers.CharField()


class ApplicantSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    first_name = serializers.CharField()
    tier = serializers.CharField()
    jobs_done = serializers.IntegerField()
    rating = serializers.FloatField(allow_null=True)
    message = serializers.CharField()
    created_at = serializers.DateTimeField()


class AcceptedBookingSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    jobber_first_name = serializers.CharField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    pay_xof = serializers.IntegerField()
