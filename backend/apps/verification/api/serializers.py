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


class ContactStepSerializer(StepSerializer):
    confirmed = serializers.IntegerField()
    pending = serializers.IntegerField()


class BriefingStepSerializer(StepSerializer):
    answered = serializers.IntegerField()
    total = serializers.IntegerField()
    new_cards = serializers.IntegerField()


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


class GuarantorSubmissionSerializer(_Captured):
    document_type = serializers.CharField(max_length=30)
    photo = serializers.FileField()
    # Length is checked by the service, which strips blanks first.
    guarantor_name = serializers.CharField(allow_blank=True, trim_whitespace=True)
    guarantor_phone = serializers.CharField(max_length=30)
    relationship = serializers.CharField(max_length=20)


class JobberChecklistSerializer(serializers.Serializer):
    """Statuses only: never the guarantor's name or phone, the bill or the identity fields."""

    tier = serializers.CharField()
    review_hours = serializers.IntegerField()
    required = serializers.ListField(child=serializers.CharField())
    identity = StepSerializer()
    guarantor = StepSerializer()
    trusted_contact = ContactStepSerializer()
    briefing = BriefingStepSerializer()


class ContactInputSerializer(serializers.Serializer):
    """Only the shape is checked here; the service owns every rule and its error code."""

    name = serializers.CharField(allow_blank=True, trim_whitespace=False, max_length=500)
    phone = serializers.CharField(allow_blank=True, max_length=50)
    relationship = serializers.CharField(allow_blank=True, max_length=30)


class ContactCodeSerializer(serializers.Serializer):
    code = serializers.CharField(allow_blank=True, max_length=20)


class ContactSerializer(serializers.Serializer):
    """The jobber's own label for a contact. Never the phone, a code or a hash."""

    id = serializers.UUIDField()
    name = serializers.CharField()
    relationship = serializers.CharField()
    status = serializers.CharField()
    replaces = serializers.UUIDField(allow_null=True)
    awaiting_code = serializers.BooleanField()
    ends_at = serializers.DateTimeField(allow_null=True)


class ContactListSerializer(serializers.Serializer):
    max = serializers.IntegerField()
    contacts = ContactSerializer(many=True)


class BriefingCardSerializer(serializers.Serializer):
    """Never the right answer or the explanation."""

    id = serializers.UUIDField()
    title = serializers.CharField()
    body = serializers.CharField()
    question = serializers.CharField()
    choices = serializers.ListField(child=serializers.CharField())
    answered = serializers.BooleanField()


class BriefingSerializer(serializers.Serializer):
    progress = BriefingStepSerializer()
    cards = BriefingCardSerializer(many=True)


class AnswerInputSerializer(serializers.Serializer):
    choice = serializers.IntegerField()


class AnswerResultSerializer(serializers.Serializer):
    correct = serializers.BooleanField()
    explanation = serializers.CharField()
    complete = serializers.BooleanField()
