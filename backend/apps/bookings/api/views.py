"""Householder endpoints for applications. Rules stay in the services; views only translate HTTP."""

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsHouseholder
from apps.bookings.models import Application
from apps.bookings.services import applications
from apps.bookings.services.applications import BookingError, first_name
from apps.listings.models import Offer

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
        return Response({"results": ApplicantSerializer(rows, many=True).data})


class AcceptView(APIView):
    permission_classes = [IsHouseholder]

    @extend_schema(request=None, responses={201: AcceptedBookingSerializer})
    def post(self, request, pk, application_id):
        offer = get_object_or_404(Offer, pk=pk, author=request.user)
        application = get_object_or_404(Application, pk=application_id, offer=offer)
        try:
            booking = applications.accept(request.user, application.pk)
        except BookingError as exc:
            return failure(exc)
        data = {
            "id": booking.pk,
            "status": booking.status,
            "jobber_first_name": first_name(booking.jobber),
            "category_name": booking.category_name,
            "starts_at": booking.starts_at,
            "pay_xof": booking.pay_xof,
        }
        return Response(AcceptedBookingSerializer(data).data, status=201)
