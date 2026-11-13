"""Jobber verification endpoints. Rules stay in the services; views only translate HTTP."""

from drf_spectacular.utils import extend_schema
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsJobber
from apps.verification.services import submissions, tiers
from apps.verification.services.submissions import VerificationError

from .serializers import (
    GuarantorSubmissionSerializer,
    IdentitySubmissionSerializer,
    JobberChecklistSerializer,
)
from .views import _failure, _read


class _JobberView(APIView):
    permission_classes = [IsJobber]

    def checklist(self, request, status=200) -> Response:
        return Response(tiers.jobber_checklist(request.user), status=status)


class JobberChecklistView(_JobberView):
    @extend_schema(responses=JobberChecklistSerializer)
    def get(self, request):
        return self.checklist(request)


class JobberIdentityView(_JobberView):
    parser_classes = [MultiPartParser]

    @extend_schema(request=IdentitySubmissionSerializer, responses=JobberChecklistSerializer)
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


class JobberGuarantorView(_JobberView):
    parser_classes = [MultiPartParser]

    @extend_schema(request=GuarantorSubmissionSerializer, responses=JobberChecklistSerializer)
    def post(self, request):
        serializer = GuarantorSubmissionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            submissions.submit_guarantor(
                request.user,
                document_type=data["document_type"],
                photo=_read(data["photo"]),
                guarantor_name=data["guarantor_name"],
                guarantor_phone=data["guarantor_phone"],
                relationship=data["relationship"],
                captured_at=data["captured_at"],
                position=serializer.position(),
            )
        except VerificationError as exc:
            return _failure(exc)
        return self.checklist(request, status=201)
