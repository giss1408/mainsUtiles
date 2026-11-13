"""Householder endpoints for applications. Rules stay in the services; views only translate HTTP."""

from drf_spectacular.utils import extend_schema
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsHouseholder
from apps.bookings.services import applications, payments
from apps.bookings.services.applications import BookingError, first_names

from .serializers import AcceptedBookingSerializer, ApplicantSerializer

NOT_FOUND = "Offre introuvable."


def failure(exc: BookingError):
    if exc.code == "forbidden":
        return Response({"error": "not_found", "message": NOT_FOUND}, status=404)
    return error_response(exc.code)


class ApplicantsView(APIView):
    permission_classes = [IsHouseholder]

    @extend_schema(responses=ApplicantSerializer(many=True))
    def get(self, request, pk):
        try:
            rows = applications.applicants(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        return Response(
            {
                "results": ApplicantSerializer(rows, many=True).data,
                # Without a payment method nobody can be accepted: the app says so up front.
                "payment_available": payments.available(),
            }
        )


class AcceptView(APIView):
    permission_classes = [IsHouseholder]

    @extend_schema(request=None, responses={201: AcceptedBookingSerializer})
    def post(self, request, pk, application_id):
        try:
            booking = applications.accept(request.user, application_id, offer_id=pk)
        except BookingError as exc:
            return failure(exc)
        names = first_names([booking.jobber_id])
        data = {
            "id": booking.pk,
            "status": booking.status,
            "jobber_first_name": names.get(booking.jobber_id, ""),
            "category_name": booking.category_name,
            "starts_at": booking.starts_at,
            "pay_xof": booking.pay_xof,
        }
        return Response(AcceptedBookingSerializer(data).data, status=201)
