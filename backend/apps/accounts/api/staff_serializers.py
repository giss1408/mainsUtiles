from rest_framework import serializers

from apps.accounts.models import DeviceEnrolmentRequest

from .serializers import validate_public_key

QUEUE_STATUSES = ["pending", "held", "approved", "code_sent"]


class StaffDeviceSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(max_length=200, trim_whitespace=False)
    device_id = serializers.UUIDField()
    device_model = serializers.CharField(max_length=120, allow_blank=True, default="")
    platform = serializers.ChoiceField(choices=["android", "ios"])
    public_key = serializers.CharField(max_length=100, validators=[validate_public_key])


class StaffDeviceStatusSerializer(serializers.Serializer):
    status = serializers.CharField()


class StaffLoginSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(max_length=200, trim_whitespace=False)
    device_id = serializers.UUIDField()
    nonce = serializers.CharField(max_length=200)
    signature = serializers.CharField(max_length=200)


class StaffMeSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    username = serializers.CharField()
    permissions = serializers.ListField(child=serializers.CharField())


class QueueFilterSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=QUEUE_STATUSES, default="pending")


class EnrolmentItemSerializer(serializers.ModelSerializer):
    """What staff see in the queue. Hashes and tokens are never included."""

    class Meta:
        model = DeviceEnrolmentRequest
        fields = [
            "id",
            "phone",
            "role",
            "kind",
            "status",
            "flags",
            "device_model",
            "platform",
            "integrity_verdict",
            "created_at",
        ]
        read_only_fields = fields


class EnrolmentDetailSerializer(EnrolmentItemSerializer):
    class Meta(EnrolmentItemSerializer.Meta):
        fields = [*EnrolmentItemSerializer.Meta.fields, "reason", "approved_at", "sent_at"]
        read_only_fields = fields


class ReasonSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=500)


class WhatsAppUrlSerializer(serializers.Serializer):
    whatsapp_url = serializers.CharField()
