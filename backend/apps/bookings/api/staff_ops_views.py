"""Staff app endpoints for the day-to-day operations: messages to send on WhatsApp, payouts,
disputes and the counts of what waits. Rules stay in the services; views only translate HTTP.

A text, a phone or a number is shown only to the staff who may act on it, only while the item is
waiting in their queue, and is never cached."""

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import HasStaffPermission, IsStaffMember
from apps.bookings.models import Message, Payout, Report
from apps.bookings.services import alerts, messages, payouts, reports
from apps.bookings.services.errors import BookingError

from .serializers import (
    AlertsSerializer,
    DisputeDetailSerializer,
    DisputeItemSerializer,
    MessageDetailSerializer,
    MessageItemSerializer,
    PayBodySerializer,
    PayoutDetailSerializer,
    PayoutItemSerializer,
    ResolveBodySerializer,
    WhatsAppLinkSerializer,
)

CanSendMessages = HasStaffPermission("bookings.send_message")
CanPay = HasStaffPermission("bookings.make_payout")
CanResolve = HasStaffPermission("bookings.resolve_dispute")


def _not_found(what: str) -> Response:
    return _no_store(Response({"error": "not_found", "message": f"{what} introuvable."}, status=404))


def _no_store(response):
    response["Cache-Control"] = "no-store"
    return response


def _refused(exc: BookingError) -> Response:
    return _no_store(error_response(exc.code, 403 if exc.code == "forbidden" else None))


class _Pagination(PageNumberPagination):
    page_size = 20


def _page(view, request, rows, to_item, serializer):
    paginator = _Pagination()
    page = paginator.paginate_queryset(rows, request, view=view)
    return _no_store(
        paginator.get_paginated_response(serializer([to_item(row) for row in page], many=True).data)
    )


# ---- Messages -----------------------------------------------------------------------------------


def _message_item(message: Message) -> dict:
    return {
        "id": message.pk,
        "kind": message.kind,
        "kind_label": message.get_kind_display(),
        "recipient_role": message.recipient.role,
        "urgent": message.urgent,
        "late": messages.is_late(message),
        "created_at": message.created_at,
    }


class MessageQueueView(APIView):
    permission_classes = [CanSendMessages]

    @extend_schema(responses=MessageItemSerializer(many=True))
    def get(self, request):
        return _page(self, request, messages.send_queue(), _message_item, MessageItemSerializer)


def _pending_message(pk) -> Message | None:
    """Only a message still waiting can be opened or sent."""
    return messages.send_queue().filter(pk=pk).first()


class MessageDetailView(APIView):
    permission_classes = [CanSendMessages]

    @extend_schema(responses=MessageDetailSerializer)
    def get(self, request, pk):
        message = _pending_message(pk)
        if message is None:
            return _not_found("Message")
        try:
            body = {**_message_item(message), **messages.preview(message, staff=request.user)}
        except BookingError as exc:
            return _refused(exc)
        return _no_store(Response(MessageDetailSerializer(body).data))


class MessageSendView(APIView):
    permission_classes = [CanSendMessages]

    @extend_schema(request=None, responses=WhatsAppLinkSerializer)
    def post(self, request, pk):
        message = get_object_or_404(Message, pk=pk)
        try:
            url = messages.send(message, staff=request.user)
        except BookingError as exc:
            return _refused(exc)
        return _no_store(Response({"whatsapp_url": url}))


# ---- Payouts ------------------------------------------------------------------------------------


def _payout_item(payout: Payout) -> dict:
    return {
        "id": payout.pk,
        "category_name": payout.booking.category_name,
        "amount_xof": payout.amount_xof,
        "due_at": payout.due_at,
        "late": payouts.is_late(payout),
    }


class PayoutQueueView(APIView):
    permission_classes = [CanPay]

    @extend_schema(responses=PayoutItemSerializer(many=True))
    def get(self, request):
        rows = payouts.payout_queue(staff=request.user).order_by("due_at", "pk")
        return _page(self, request, rows, _payout_item, PayoutItemSerializer)


class PayoutDetailView(APIView):
    permission_classes = [CanPay]

    @extend_schema(responses=PayoutDetailSerializer)
    def get(self, request, pk):
        payout = payouts.payout_queue(staff=request.user).filter(pk=pk).first()
        if payout is None:
            return _not_found("Paiement")
        details = payouts.payout_details(payout, staff=request.user)  # audited there
        body = {
            **_payout_item(payout),
            "jobber_phone": details["jobber_phone"],
            "completed_at": details["completed_at"],
            "payable": payouts.payable(payout),
        }
        return _no_store(Response(PayoutDetailSerializer(body).data))


class PayoutPayView(APIView):
    permission_classes = [CanPay]

    @extend_schema(request=PayBodySerializer, responses=PayoutItemSerializer)
    def post(self, request, pk):
        body = PayBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        payout = get_object_or_404(Payout.objects.select_related("booking"), pk=pk)
        try:
            payouts.record_payout(payout, staff=request.user, reference=body.validated_data["reference"])
        except BookingError as exc:
            return _refused(exc)
        return _no_store(Response(PayoutItemSerializer(_payout_item(payout)).data))


# ---- Disputes -----------------------------------------------------------------------------------


def _dispute_item(report: Report) -> dict:
    return {
        "id": report.pk,
        "category_name": report.booking.category_name,
        "created_at": report.created_at,
        "late": reports.is_late(report),
    }


class DisputeQueueView(APIView):
    permission_classes = [CanResolve]

    @extend_schema(responses=DisputeItemSerializer(many=True))
    def get(self, request):
        return _page(self, request, reports.dispute_queue(), _dispute_item, DisputeItemSerializer)


class DisputeDetailView(APIView):
    permission_classes = [CanResolve]

    @extend_schema(responses=DisputeDetailSerializer)
    def get(self, request, pk):
        report = reports.dispute_queue().filter(pk=pk).first()
        if report is None:
            return _not_found("Litige")
        body = {**_dispute_item(report), **reports.report_details(report, staff=request.user)}
        return _no_store(Response(DisputeDetailSerializer(body).data))


class DisputeResolveView(APIView):
    permission_classes = [CanResolve]

    @extend_schema(request=ResolveBodySerializer, responses=DisputeItemSerializer)
    def post(self, request, pk):
        body = ResolveBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        report = get_object_or_404(Report.objects.select_related("booking"), pk=pk)
        data = body.validated_data
        try:
            reports.resolve_dispute(
                report,
                staff=request.user,
                outcome=data["outcome"],
                note=data["note"],
                jobber_xof=data["jobber_xof"],
            )
        except BookingError as exc:
            return _refused(exc)
        return _no_store(Response(DisputeItemSerializer(_dispute_item(report)).data))


# ---- Alerts -------------------------------------------------------------------------------------


class AlertsView(APIView):
    permission_classes = [IsStaffMember]

    @extend_schema(responses=AlertsSerializer)
    def get(self, request):
        return _no_store(Response(AlertsSerializer(alerts.counts(request.user)).data))
