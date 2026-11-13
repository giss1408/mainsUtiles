"""Payment and booking endpoints. Rules stay in the services; views only translate HTTP."""

from django.conf import settings
from django.http import HttpResponse
from drf_spectacular.utils import extend_schema
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsHouseholder
from apps.bookings.services import bookings, payments
from apps.bookings.services.errors import BookingError
from apps.listings.api.jobber_views import IsJobberRole

from .serializers import (
    AddressSerializer,
    CancelBodySerializer,
    CancelledSerializer,
    HouseholderBookingSerializer,
    PaymentBodySerializer,
    PaymentReceiptSerializer,
)

NOT_FOUND = "Réservation introuvable."


def failure(exc: BookingError):
    """Someone else's id looks like a missing one: do not reveal that it exists."""
    if exc.code == "forbidden":
        return Response({"error": "not_found", "message": NOT_FOUND}, status=404)
    return error_response(exc.code)


def no_store(response):
    response["Cache-Control"] = "no-store"
    return response


class _Householder(APIView):
    permission_classes = [IsHouseholder]


class _Jobber(APIView):
    permission_classes = [IsJobberRole]


class BookingView(_Householder):
    @extend_schema(responses=HouseholderBookingSerializer)
    def get(self, request, pk):
        try:
            data = bookings.householder_view(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        return no_store(Response(HouseholderBookingSerializer(data).data))


class PaymentView(_Householder):
    parser_classes = [MultiPartParser]

    @extend_schema(request=PaymentBodySerializer, responses={201: PaymentReceiptSerializer})
    def post(self, request, pk):
        body = PaymentBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        try:
            booking = bookings.live_booking(request.user, pk)
            if data["screenshot"].size > settings.VERIFICATION_PHOTO_MAX_BYTES:
                raise BookingError("photo_too_large")  # refused before it is read into memory
            payment = payments.submit_proof(
                request.user,
                booking.pk,
                method_id=data["method_id"],
                reference=data["reference"],
                screenshot=data["screenshot"].read(),
                captured_at=data["captured_at"],
            )
        except BookingError as exc:
            return failure(exc)
        return Response(
            PaymentReceiptSerializer({"id": payment.pk, "status": payment.status}).data, status=201
        )


class PhotoView(_Householder):
    @extend_schema(responses={200: bytes})
    def get(self, request, pk):
        try:
            data = bookings.householder_photo(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        # A face must never be kept by a cache.
        return no_store(HttpResponse(data, content_type="image/jpeg"))


class CancelView(_Householder):
    @extend_schema(request=CancelBodySerializer, responses=CancelledSerializer)
    def post(self, request, pk):
        body = CancelBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        try:
            booking = bookings.live_booking(request.user, pk)
            cancelled = bookings.cancel(request.user, booking.pk, reason=body.validated_data["reason"])
        except BookingError as exc:
            return failure(exc)
        return Response(CancelledSerializer({"id": cancelled.pk, "status": cancelled.status}).data)


class AddressView(_Jobber):
    @extend_schema(responses=AddressSerializer)
    def get(self, request, pk):
        try:
            data = bookings.address_for(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        # An address must never be kept by a cache.
        return no_store(Response(AddressSerializer(data).data))


class JobberCancelView(_Jobber):
    @extend_schema(request=CancelBodySerializer, responses=CancelledSerializer)
    def post(self, request, pk):
        body = CancelBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        try:
            cancelled = bookings.cancel(request.user, pk, reason=body.validated_data["reason"])
        except BookingError as exc:
            return failure(exc)
        return Response(CancelledSerializer({"id": cancelled.pk, "status": cancelled.status}).data)
