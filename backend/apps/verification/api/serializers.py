from rest_framework import serializers


class _Captured(serializers.Serializer):
    """When and, if known, where the app took the photos."""

    captured_at = serializers.DateTimeField()
    lat = serializers.FloatField(required=False, allow_null=True, min_value=-90, max_value=90)
    lng = serializers.FloatField(required=False, allow_null=True, min_value=-180, max_value=180)

    def position(self) -> tuple[float, float] | None:
        lat, lng = self.validated_data.get("lat"), self.validated_data.get("lng")
        return (lat, lng) if lat is not None and lng is not None else None


class IdentitySubmissionSerializer(_Captured):
    document_type = serializers.CharField(max_length=30)
    front = serializers.FileField()
    back = serializers.FileField()
    selfie = serializers.FileField()


class AddressSubmissionSerializer(_Captured):
    document_type = serializers.CharField(max_length=30)
    photo = serializers.FileField()
    commune = serializers.CharField(max_length=60)
    quartier = serializers.CharField(max_length=80, allow_blank=True, trim_whitespace=True)


class HomeLocationSerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    accuracy_m = serializers.FloatField(min_value=0)
    mock_location = serializers.BooleanField(default=False)
    captured_at = serializers.DateTimeField()


class StepSerializer(serializers.Serializer):
    status = serializers.CharField()
    reason = serializers.CharField(allow_blank=True)


class AddressStepSerializer(StepSerializer):
    commune = serializers.CharField(allow_blank=True)
    quartier = serializers.CharField(allow_blank=True)
    expires_at = serializers.DateTimeField(allow_null=True)


class ChecklistSerializer(serializers.Serializer):
    """Shape of every response. Statuses only: no identity fields, photos or coordinates."""

    tier = serializers.CharField()
    review_hours = serializers.IntegerField()
    communes = serializers.ListField(child=serializers.CharField())
    identity = StepSerializer()
    address = AddressStepSerializer()
    home_location = StepSerializer()
