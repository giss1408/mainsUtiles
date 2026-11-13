"""Staff app endpoints for trusted contacts. Rules stay in the services; views only translate HTTP.

The contact's number never leaves the server as text: it travels only inside the one-time WhatsApp
link, which is never cached."""

from django.conf import settings
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import HasStaffPermission
from apps.audit.services import record as audit
from apps.providers import registry
from apps.verification.models import IdentityVerification, Status, TrustedContact
from apps.verification.services import contacts
from apps.verification.services.encryption import decrypt_text
from apps.verification.services.submissions import VerificationError
from apps.verification.services.tiers import current_record

CanSend = HasStaffPermission(contacts.SEND_CODE)
NO_STORE = {"Cache-Control": "no-store"}


def _jobber_name(contact: TrustedContact) -> str | None:
    identity = current_record(IdentityVerification, contact.user)
    if identity is None or identity.status != Status.CONFIRMED:
        return None
    return decrypt_text(identity.full_name)


def _action(contact: TrustedContact) -> str:
    return "send" if contact.status == "pending" else "notice"


class ContactItemSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    relationship = serializers.CharField()
    action = serializers.CharField()
    created_at = serializers.DateTimeField()


class ContactDetailSerializer(ContactItemSerializer):
    name = serializers.CharField()
    jobber_name = serializers.CharField(allow_null=True)


class ContactFilterSerializer(serializers.Serializer):
    file = serializers.ChoiceField(choices=["send", "notice"], default="send")


class WhatsAppUrlSerializer(serializers.Serializer):
    whatsapp_url = serializers.CharField()


class _Pagination(PageNumberPagination):
    page_size = 20


def _item(contact: TrustedContact) -> dict:
    return {
        "id": contact.pk,
        "relationship": contact.relationship,
        "action": _action(contact),
        "created_at": contact.created_at,
    }


class ContactQueueView(APIView):
    permission_classes = [CanSend]

    @extend_schema(parameters=[ContactFilterSerializer], responses=ContactItemSerializer(many=True))
    def get(self, request):
        filters = ContactFilterSerializer(data=request.query_params)
        filters.is_valid(raise_exception=True)
        rows = (
            contacts.notice_queue() if filters.validated_data["file"] == "notice" else contacts.send_queue()
        )
        paginator = _Pagination()
        page = paginator.paginate_queryset(rows, request, view=self)
        response = paginator.get_paginated_response([_item(c) for c in page])
        response["Cache-Control"] = "no-store"
        return response


class ContactDetailView(APIView):
    permission_classes = [CanSend]

    @extend_schema(responses=ContactDetailSerializer)
    def get(self, request, pk):
        contact = get_object_or_404(TrustedContact.objects.select_related("user"), pk=pk)
        audit(request.user, "verification.contact.view", contact)
        body = {**_item(contact), "name": decrypt_text(contact.name), "jobber_name": _jobber_name(contact)}
        return Response(body, headers=NO_STORE)


def _link(contact: TrustedContact, message: str) -> Response:
    url = registry.get_messaging().whatsapp_link(decrypt_text(contact.phone), message)
    return Response({"whatsapp_url": url}, headers=NO_STORE)


class ContactSendView(APIView):
    permission_classes = [CanSend]

    @extend_schema(request=None, responses=WhatsAppUrlSerializer)
    def post(self, request, pk):
        contact = get_object_or_404(TrustedContact, pk=pk)
        try:
            code = contacts.send_code(contact, staff=request.user)
        except VerificationError as exc:
            return error_response(exc.code)
        return _link(contact, contacts.CONTACT_MESSAGE.format(code=code))


class ContactNoticeView(APIView):
    permission_classes = [CanSend]

    @extend_schema(request=None, responses=WhatsAppUrlSerializer)
    def post(self, request, pk):
        contact = get_object_or_404(TrustedContact, pk=pk)
        try:
            contacts.record_notice(contact, staff=request.user)
        except VerificationError as exc:
            return error_response(exc.code)
        return _link(contact, contacts.NOTICE_MESSAGE.format(n=settings.TRUSTED_CONTACT_CHANGE_DELAY_HOURS))
