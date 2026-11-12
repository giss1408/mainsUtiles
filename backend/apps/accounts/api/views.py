from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DeviceEnrolmentRequest
from apps.accounts.services import enrolment
from apps.core.net import client_ip

from .errors import error_response
from .serializers import (
    ApplicationCreateSerializer,
    ApplicationStatusSerializer,
    ConfirmResultSerializer,
    ConfirmSerializer,
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
