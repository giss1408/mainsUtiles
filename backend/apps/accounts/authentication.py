import jwt
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed

from apps.accounts.models import Device
from apps.accounts.services.device_auth import decode_access


class DeviceJWTAuthentication(BaseAuthentication):
    """Authenticates `Authorization: Bearer <access token>`; request.auth is the Device."""

    keyword = "Bearer"

    def authenticate_header(self, request):
        return self.keyword

    def authenticate(self, request):
        parts = get_authorization_header(request).split()
        if not parts or parts[0].lower() != b"bearer":
            return None
        if len(parts) != 2:
            raise AuthenticationFailed({"error": "token_invalid"})
        try:
            claims = decode_access(parts[1].decode())
        except (jwt.PyJWTError, UnicodeDecodeError) as exc:
            raise AuthenticationFailed({"error": "token_invalid"}) from exc
        device = Device.objects.select_related("user").filter(pk=claims.get("did")).first()
        if (
            device is None
            or device.status != Device.Status.ACTIVE
            or not device.user.is_active
            or str(device.user_id) != claims.get("sub")
        ):
            raise AuthenticationFailed({"error": "device_revoked"})
        return (device.user, device)
