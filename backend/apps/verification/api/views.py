"""Householder verification endpoints. Rules stay in the services; views only translate HTTP."""

from django.conf import settings
from drf_spectacular.utils import extend_schema
from rest_framework.parsers import JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsHouseholder
from apps.verification.services import submissions, tiers
from apps.verification.services.submissions import VerificationError

from .serializers import (
    AddressSubmissionSerializer,
    ChecklistSerializer,
    HomeLocationSerializer,
    IdentitySubmissionSerializer,
)

ALREADY_SENT = "Cette étape est déjà envoyée."


def _failure(exc: VerificationError) -> Response:
    if exc.code == "invalid_state":
        return Response({"error": exc.code, "message": ALREADY_SENT}, status=409)
    if exc.code == "forbidden":
        return Response({"error": exc.code, "message": ""}, status=403)
    return error_response(exc.code)


def _read(upload) -> bytes:
    """Refuse an oversized upload before reading it into memory."""
    if upload.size > settings.VERIFICATION_PHOTO_MAX_BYTES:
        raise VerificationError("photo_too_large")
    return upload.read()


class _HouseholderView(APIView):
    permission_classes = [IsHouseholder]

    def checklist(self, request, status=200) -> Response:
        return Response(tiers.checklist(request.user), status=status)


class ChecklistView(_HouseholderView):
    @extend_schema(responses=ChecklistSerializer)
    def get(self, request):
        return self.checklist(request)


class IdentityView(_HouseholderView):
    parser_classes = [MultiPartParser]

    @extend_schema(request=IdentitySubmissionSerializer, responses=ChecklistSerializer)
    def post(self, request):
        serializer = IdentitySubmissionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            submissions.submit_identity(
                request.user,
                document_type=data["document_type"],
                front=_read(data["front"]),
                back=_read(data["back"]),
                selfie=_read(data["selfie"]),
                captured_at=data["captured_at"],
                position=serializer.position(),
            )
        except VerificationError as exc:
            return _failure(exc)
        return self.checklist(request, status=201)


class AddressView(_HouseholderView):
    parser_classes = [MultiPartParser]

    @extend_schema(request=AddressSubmissionSerializer, responses=ChecklistSerializer)
    def post(self, request):
        serializer = AddressSubmissionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            submissions.submit_address_proof(
                request.user,
                document_type=data["document_type"],
                photo=_read(data["photo"]),
                commune=data["commune"],
                quartier=data["quartier"],
                captured_at=data["captured_at"],
                position=serializer.position(),
            )
        except VerificationError as exc:
            return _failure(exc)
        return self.checklist(request, status=201)


class HomeLocationView(_HouseholderView):
    parser_classes = [JSONParser]

    @extend_schema(request=HomeLocationSerializer, responses=ChecklistSerializer)
    def post(self, request):
        serializer = HomeLocationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            submissions.record_home_location(request.user, **serializer.validated_data)
        except VerificationError as exc:
            return _failure(exc)
        return self.checklist(request, status=201)
