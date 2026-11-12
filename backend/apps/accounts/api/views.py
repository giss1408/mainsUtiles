from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DeviceEnrolmentRequest
from apps.accounts.services import device_auth, enrolment
from apps.core.net import client_ip

from .errors import error_response
from .serializers import (
    ApplicationCreateSerializer,
    ApplicationStatusSerializer,
    ChallengeSerializer,
    ConfirmResultSerializer,
    ConfirmSerializer,
    MeSerializer,
    NonceSerializer,
    RefreshSerializer,
    TokenPairSerializer,
    TokenRequestSerializer,
)

TOKEN_HEADER = "X-Enrolment-Token"


class PublicView(APIView):
    """Enrolment happens before the device has any credentials."""

    authentication_classes = []
    permission_classes = [AllowAny]


def _find(request, application_id):
    """Return the application only to the device that created it."""
    req = DeviceEnrolmentRequest.objects.filter(pk=application_id).first()
    token = request.headers.get(TOKEN_HEADER, "")
    if req is None or not enrolment.check_client_token(req, token):
        return None, token
    return req, token


class ApplicationCreateView(PublicView):
    @extend_schema(request=ApplicationCreateSerializer, responses=ApplicationStatusSerializer)
    def post(self, request):
        serializer = ApplicationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        before = DeviceEnrolmentRequest.objects.count()
        try:
            req = enrolment.apply(ip=client_ip(request), **serializer.validated_data)
        except enrolment.EnrolmentError as exc:
            return error_response(exc.code)
        created = DeviceEnrolmentRequest.objects.count() > before
        return Response(ApplicationStatusSerializer(req).data, status=201 if created else 200)


class ApplicationStatusView(PublicView):
    @extend_schema(responses=ApplicationStatusSerializer)
    def get(self, request, id):
        req, _ = _find(request, id)
        if req is None:
            return error_response("forbidden")
        return Response(ApplicationStatusSerializer(req).data)


class ApplicationConfirmView(PublicView):
    @extend_schema(request=ConfirmSerializer, responses=ConfirmResultSerializer)
    def post(self, request, id):
        req, token = _find(request, id)
        if req is None:
            return error_response("forbidden")
        serializer = ConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            device = enrolment.confirm(req, client_token=token, code=serializer.validated_data["code"])
        except enrolment.EnrolmentError as exc:
            return error_response(exc.code)
        return Response({"status": "completed", "device_id": str(device.pk)})


def auth_error(exc: device_auth.AuthError) -> Response:
    return Response({"error": exc.code}, status=423 if exc.code == "locked" else 401)


class ChallengeView(PublicView):
    @extend_schema(request=ChallengeSerializer, responses=NonceSerializer)
    def post(self, request):
        serializer = ChallengeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response({"nonce": device_auth.create_challenge(serializer.validated_data["device_id"])})


class TokenView(PublicView):
    @extend_schema(request=TokenRequestSerializer, responses=TokenPairSerializer)
    def post(self, request):
        serializer = TokenRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            pair = device_auth.sign_in(data["device_id"], data["nonce"], data["signature"])
        except device_auth.AuthError as exc:
            return auth_error(exc)
        return Response({"access": pair.access, "refresh": pair.refresh})


class RefreshView(PublicView):
    @extend_schema(request=RefreshSerializer, responses=TokenPairSerializer)
    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            pair = device_auth.rotate(serializer.validated_data["refresh"])
        except device_auth.AuthError as exc:
            return auth_error(exc)
        return Response({"access": pair.access, "refresh": pair.refresh})


class MeView(APIView):
    @extend_schema(responses=MeSerializer)
    def get(self, request):
        return Response(
            {
                "id": str(request.user.pk),
                "phone": request.user.phone,
                "role": request.user.role,
                "device_id": str(request.auth.pk),
            }
        )
