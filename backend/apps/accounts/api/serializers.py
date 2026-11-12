import base64
import binascii

from django.conf import settings
from rest_framework import serializers

from apps.accounts.models import DeviceEnrolmentRequest

Status = DeviceEnrolmentRequest.Status

# What the app is told. Internal review steps are not exposed.
CLIENT_STATUS = {
    Status.PENDING: "pending",
    Status.APPROVED: "pending",
    Status.HELD: "held",
    Status.CODE_SENT: "awaiting_code",
    Status.COMPLETED: "completed",
    Status.REFUSED: "refused",
    Status.EXPIRED: "expired",
    Status.LOCKED: "locked",
}


def validate_public_key(value: str) -> str:
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise serializers.ValidationError("Clé publique invalide.") from exc
    if len(raw) != 32:
        raise serializers.ValidationError("Clé publique invalide.")
    return value


class ApplicationCreateSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=30)
    role = serializers.ChoiceField(choices=["householder", "jobber"])
    device_id = serializers.UUIDField()
    device_model = serializers.CharField(max_length=120, allow_blank=True, default="")
    platform = serializers.ChoiceField(choices=["android", "ios"])
    public_key = serializers.CharField(max_length=100, validators=[validate_public_key])
    client_token = serializers.CharField(min_length=3, max_length=200)
    approx_lat = serializers.FloatField(required=False, allow_null=True, min_value=-90, max_value=90)
    approx_lng = serializers.FloatField(required=False, allow_null=True, min_value=-180, max_value=180)


class ApplicationStatusSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.SerializerMethodField()
    kind = serializers.CharField()
    reason = serializers.SerializerMethodField()
    response_hours = serializers.SerializerMethodField()

    def get_status(self, obj) -> str:
        return CLIENT_STATUS[obj.status]

    def get_reason(self, obj) -> str:
        return obj.reason if obj.status in (Status.REFUSED, Status.HELD) else ""

    def get_response_hours(self, obj) -> int:
        return settings.ENROLMENT_RESPONSE_HOURS


class ConfirmSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=12)


class ConfirmResultSerializer(serializers.Serializer):
    status = serializers.CharField()
    device_id = serializers.UUIDField()


class ChallengeSerializer(serializers.Serializer):
    device_id = serializers.UUIDField()


class NonceSerializer(serializers.Serializer):
    nonce = serializers.CharField()


class TokenRequestSerializer(serializers.Serializer):
    device_id = serializers.UUIDField()
    nonce = serializers.CharField(max_length=200)
    signature = serializers.CharField(max_length=200)


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField(max_length=200)


class TokenPairSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class MeSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    phone = serializers.CharField()
    role = serializers.CharField()
    device_id = serializers.UUIDField()
