"""Staff app endpoints for payments. Rules stay in the services; views only translate HTTP.

A reference or a receipt is shown only to the staff who may act on it, only while the payment is
waiting in their queue, and is never cached."""

from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.serializers import ChoiceField, Serializer
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsStaffMember
from apps.audit.services import record as audit
from apps.bookings.models import Payment
from apps.bookings.services import payments
from apps.bookings.services.errors import BookingError
from apps.verification.services.encryption import decrypt_text

from .serializers import (
    ConfirmBodySerializer,
    PaymentDetailSerializer,
    PaymentItemSerializer,
    RefundBodySerializer,
    RefuseBodySerializer,
)

VERIFY = "bookings.verify_payment"
REFUND = "bookings.make_refund"
NOT_FOUND = {"error": "not_found", "message": "Paiement introuvable."}


class CanWorkPayments(IsStaffMember):
    """A staff account that may check payments or record refunds."""

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not super().has_permission(request, view):
            return False
        return user.has_perm(VERIFY) or user.has_perm(REFUND)


class FileSerializer(Serializer):
    file = ChoiceField(choices=["check", "refund"], default="check")


def _queue_of(user, payment: Payment) -> str | None:
    """`check` or `refund` when this staff member may work the payment as it stands, else None."""
    if payment.status == Payment.Status.SUBMITTED and user.has_perm(VERIFY):
        return "check"
    if payment.status == Payment.Status.REFUND_DUE and user.has_perm(REFUND):
        return "refund"
    return None


def _item(payment: Payment, action: str) -> dict:
    return {
        "id": payment.pk,
        "category_name": payment.booking.category_name,
        "starts_at": payment.booking.starts_at,
        "amount_xof": payments.refund_amount(payment) if action == "refund" else payment.amount_xof,
        "method_label": payment.method.get_provider_display(),
        "submitted_at": payment.submitted_at,
        "late": payments.is_late(payment),
        "action": action,
    }


def _no_store(response):
    response["Cache-Control"] = "no-store"
    return response


class _Pagination(PageNumberPagination):
    page_size = 20


class PaymentQueueView(APIView):
    permission_classes = [CanWorkPayments]

    @extend_schema(parameters=[FileSerializer], responses=PaymentItemSerializer(many=True))
    def get(self, request):
        filters = FileSerializer(data=request.query_params)
        filters.is_valid(raise_exception=True)
        file = filters.validated_data["file"]
        if not request.user.has_perm(VERIFY if file == "check" else REFUND):
            raise PermissionDenied
        rows = payments.check_queue() if file == "check" else payments.refund_queue()
        paginator = _Pagination()
        page = paginator.paginate_queryset(rows.order_by("submitted_at", "pk"), request, view=self)
        response = paginator.get_paginated_response(
            PaymentItemSerializer([_item(p, file) for p in page], many=True).data
        )
        return _no_store(response)


def _queued(request, pk) -> tuple[Payment, str]:
    payment = get_object_or_404(Payment.objects.select_related("booking", "method", "proof"), pk=pk)
    action = _queue_of(request.user, payment)
    if action is None:
        raise PaymentNotFound
    return payment, action


class PaymentNotFound(Exception):
    pass


class PaymentDetailView(APIView):
    permission_classes = [CanWorkPayments]

    @extend_schema(responses=PaymentDetailSerializer)
    def get(self, request, pk):
        try:
            payment, action = _queued(request, pk)
        except PaymentNotFound:
            return Response(NOT_FOUND, status=404)
        audit(request.user, "booking.payment.view", payment, booking=str(payment.booking_id))
        body = {
            **_item(payment, action),
            "fee_xof": payment.fee_xof,
            "reference": decrypt_text(payment.reference),
            "method_number": payment.method.number,
            "seen_before": payments.proof_seen_before(payment),
            "status": payment.status,
        }
        return _no_store(Response(PaymentDetailSerializer(body).data))


class PaymentProofView(APIView):
    permission_classes = [CanWorkPayments]

    @extend_schema(responses={200: bytes})
    def get(self, request, pk):
        try:
            payment, _ = _queued(request, pk)
        except PaymentNotFound:
            return Response(NOT_FOUND, status=404)
        try:
            data = payments.read_proof(payment, staff=request.user)
        except BookingError as exc:
            return error_response(exc.code, 403 if exc.code == "forbidden" else None)
        # A payment receipt must never be kept by a cache.
        return _no_store(HttpResponse(data, content_type="image/jpeg"))


class _Decision(APIView):
    permission_classes = [CanWorkPayments]

    def run(self, request, pk, action_name, call):
        payment = get_object_or_404(Payment.objects.select_related("booking", "method"), pk=pk)
        try:
            call(payment)
        except BookingError as exc:
            return error_response(exc.code, 403 if exc.code == "forbidden" else None)
        payment.refresh_from_db()
        return _no_store(Response(PaymentItemSerializer(_item(payment, action_name)).data))


class PaymentConfirmView(_Decision):
    @extend_schema(request=ConfirmBodySerializer, responses=PaymentItemSerializer)
    def post(self, request, pk):
        body = ConfirmBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        return self.run(
            request,
            pk,
            "check",
            lambda p: payments.confirm_payment(
                p,
                staff=request.user,
                amount_matches=body.validated_data["amount_matches"],
                reference_matches=body.validated_data["reference_matches"],
            ),
        )


class PaymentRefuseView(_Decision):
    @extend_schema(request=RefuseBodySerializer, responses=PaymentItemSerializer)
    def post(self, request, pk):
        body = RefuseBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        return self.run(
            request,
            pk,
            "check",
            lambda p: payments.refuse_payment(p, staff=request.user, reason=body.validated_data["reason"]),
        )


class PaymentRefundView(_Decision):
    @extend_schema(request=RefundBodySerializer, responses=PaymentItemSerializer)
    def post(self, request, pk):
        body = RefundBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        return self.run(
            request,
            pk,
            "refund",
            lambda p: payments.record_refund(
                p, staff=request.user, reference=body.validated_data["reference"]
            ),
        )
