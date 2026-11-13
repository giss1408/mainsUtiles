"""Jobber verification endpoints. Rules stay in the services; views only translate HTTP."""

from django.conf import settings
from drf_spectacular.utils import extend_schema
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsJobber
from apps.verification.services import briefing, contacts, submissions, tiers
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError

from .serializers import (
    AnswerInputSerializer,
    AnswerResultSerializer,
    BriefingSerializer,
    ContactCodeSerializer,
    ContactInputSerializer,
    ContactListSerializer,
    ContactSerializer,
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


def _contact(contact) -> dict:
    """The jobber's own label for a contact; the phone and the code never leave the server."""
    return {
        "id": str(contact.pk),
        "name": decrypt_text(contact.name),
        "relationship": contact.relationship,
        "status": contact.status,
        "replaces": str(contact.replaces_id) if contact.replaces_id else None,
        "awaiting_code": contacts.awaiting_code(contact),
        "ends_at": contacts.ends_at(contact),
    }


def _contact_failure(exc: VerificationError) -> Response:
    # `forbidden` here means "not your contact": answered as not found.
    return error_response(exc.code)


class ContactsView(_JobberView):
    @extend_schema(responses=ContactListSerializer)
    def get(self, request):
        contacts.apply_replacements(request.user)
        live = contacts.live_contacts(request.user)
        return Response({"max": settings.TRUSTED_CONTACTS_MAX, "contacts": [_contact(c) for c in live]})

    @extend_schema(request=ContactInputSerializer, responses={201: ContactSerializer})
    def post(self, request):
        serializer = ContactInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            contact = contacts.add_contact(request.user, **serializer.validated_data)
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(_contact(contact), status=201)


class ContactDetailView(_JobberView):
    """Read only: a contact is never deleted, only replaced."""

    http_method_names = ["get", "head", "options"]

    @extend_schema(responses=ContactSerializer)
    def get(self, request, pk):
        try:
            contact = contacts.own(request.user, pk)
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(_contact(contact))


class ContactCodeView(_JobberView):
    @extend_schema(request=None, responses=ContactSerializer)
    def post(self, request, pk):
        try:
            contact = contacts.request_code(request.user, pk)
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(_contact(contact))


class ContactConfirmView(_JobberView):
    @extend_schema(request=ContactCodeSerializer, responses=ContactSerializer)
    def post(self, request, pk):
        serializer = ContactCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            contact = contacts.confirm_contact(request.user, pk, serializer.validated_data["code"])
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(_contact(contact))


class ContactReplaceView(_JobberView):
    @extend_schema(request=ContactInputSerializer, responses={201: ContactSerializer})
    def post(self, request, pk):
        serializer = ContactInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            contact = contacts.replace_contact(request.user, pk, **serializer.validated_data)
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(_contact(contact), status=201)


class BriefingView(_JobberView):
    @extend_schema(responses=BriefingSerializer)
    def get(self, request):
        return Response(
            {
                "progress": briefing.briefing_progress(request.user),
                "cards": briefing.briefing_cards(request.user),
            }
        )


class BriefingAnswerView(_JobberView):
    @extend_schema(request=AnswerInputSerializer, responses=AnswerResultSerializer)
    def post(self, request, card_id):
        serializer = AnswerInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            result = briefing.answer_card(request.user, card_id, serializer.validated_data["choice"])
        except VerificationError as exc:
            return _contact_failure(exc)
        return Response(result)
