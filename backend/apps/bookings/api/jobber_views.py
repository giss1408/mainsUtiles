"""Jobber endpoints for applications. Rules stay in the services; views only translate HTTP."""

from drf_spectacular.utils import extend_schema
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.bookings.models import Booking
from apps.bookings.services import applications
from apps.bookings.services.applications import BookingError
from apps.listings.api.jobber_views import IsJobberRole

from .serializers import (
    ApplicationItemSerializer,
    ApplicationSerializer,
    ApplyBodySerializer,
    JobberBookingSerializer,
)

NOT_FOUND = "Candidature introuvable."


def failure(exc: BookingError):
    """A foreign id looks like a missing one: do not reveal that it exists."""
    if exc.code == "forbidden":
        return Response({"error": "not_found", "message": NOT_FOUND}, status=404)
    return error_response(exc.code)


def application_line(application) -> dict:
    return {
        "id": application.pk,
        "offer_id": application.offer_id,
        "status": application.status,
        "created_at": application.created_at,
    }


def application_item(application) -> dict:
    offer = application.offer
    booking = getattr(application, "booking", None)
    return {
        "id": application.pk,
        "status": application.status,
        "message": application.message,
        "created_at": application.created_at,
        "offer": {
            "id": offer.pk,
            "category_name": offer.category_name,
            "starts_at": offer.starts_at,
            "duration_minutes": offer.duration_minutes,
            "pay_xof": offer.pay_xof,
            "commune": offer.commune,
            "quartier": offer.quartier,
            "status": offer.status,
        },
        "booking": {"id": booking.pk, "status": booking.status} if booking else None,
    }


class ApplyView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(request=ApplyBodySerializer, responses={201: ApplicationSerializer})
    def post(self, request, pk):
        body = ApplyBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        try:
            application = applications.apply(request.user, pk, body.validated_data["message"])
        except BookingError as exc:
            return failure(exc)
        return Response(ApplicationSerializer(application_line(application)).data, status=201)


class MyApplicationsView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(responses=ApplicationItemSerializer(many=True))
    def get(self, request):
        rows = [application_item(a) for a in applications.my_applications(request.user)]
        return Response({"results": ApplicationItemSerializer(rows, many=True).data})


class WithdrawView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(request=None, responses=ApplicationSerializer)
    def post(self, request, pk):
        try:
            application = applications.withdraw(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        return Response(ApplicationSerializer(application_line(application)).data)


class MyBookingsView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(responses=JobberBookingSerializer(many=True))
    def get(self, request):
        rows = Booking.objects.filter(jobber=request.user).order_by("starts_at")
        return Response({"results": JobberBookingSerializer(rows, many=True).data})
