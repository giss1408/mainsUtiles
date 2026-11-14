"""The job and after: check-in, check-out, confirmation, problems and reviews. Rules stay in the
services; views only translate HTTP."""

from drf_spectacular.utils import extend_schema
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsHouseholder
from apps.bookings.services import bookings, jobs, reports, reviews
from apps.bookings.services.errors import BookingError
from apps.listings.api.jobber_views import IsJobberRole

from .payments_views import failure, no_store
from .serializers import (
    CheckInBodySerializer,
    JobStateSerializer,
    ReportBodySerializer,
    ReportReceiptSerializer,
    ReviewBodySerializer,
    ReviewStateSerializer,
)


def _state(booking) -> dict:
    return JobStateSerializer({"id": booking.pk, "status": booking.status}).data


def _report(user, booking_id, request) -> Response:
    body = ReportBodySerializer(data=request.data)
    body.is_valid(raise_exception=True)
    report = reports.report_problem(
        user, booking_id, text=body.validated_data["text"], dispute=body.validated_data["dispute"]
    )
    receipt = {"id": report.pk, "kind": report.kind, "booking_status": report.booking.status}
    return Response(ReportReceiptSerializer(receipt).data, status=201)


def _review_state(user, booking_id, status=200) -> Response:
    data = reviews.my_review_state(user, booking_id)
    return no_store(Response(ReviewStateSerializer(data).data, status=status))


def _submit_review(user, booking_id, request) -> Response:
    body = ReviewBodySerializer(data=request.data)
    body.is_valid(raise_exception=True)
    reviews.submit_review(
        user, booking_id, stars=body.validated_data["stars"], comment=body.validated_data["comment"]
    )
    return _review_state(user, booking_id, status=201)


class _Householder(APIView):
    permission_classes = [IsHouseholder]


class _Jobber(APIView):
    permission_classes = [IsJobberRole]


class CheckInView(_Jobber):
    @extend_schema(request=CheckInBodySerializer, responses=JobStateSerializer)
    def post(self, request, pk):
        body = CheckInBodySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        try:
            booking = jobs.check_in(request.user, pk, **body.validated_data)
        except BookingError as exc:
            return failure(exc)
        return Response(_state(booking))


class CheckOutView(_Jobber):
    @extend_schema(request=None, responses=JobStateSerializer)
    def post(self, request, pk):
        try:
            booking = jobs.check_out(request.user, pk)
        except BookingError as exc:
            return failure(exc)
        return Response(_state(booking))


class JobberReportView(_Jobber):
    @extend_schema(request=ReportBodySerializer, responses={201: ReportReceiptSerializer})
    def post(self, request, pk):
        try:
            return _report(request.user, pk, request)
        except BookingError as exc:
            return failure(exc)


class JobberReviewView(_Jobber):
    @extend_schema(responses=ReviewStateSerializer)
    def get(self, request, pk):
        try:
            return _review_state(request.user, pk)
        except BookingError as exc:
            return failure(exc)

    @extend_schema(request=ReviewBodySerializer, responses={201: ReviewStateSerializer})
    def post(self, request, pk):
        try:
            return _submit_review(request.user, pk, request)
        except BookingError as exc:
            return failure(exc)


class ConfirmView(_Householder):
    @extend_schema(request=None, responses=JobStateSerializer)
    def post(self, request, pk):
        try:
            booking = jobs.confirm_done(request.user, bookings.offer_booking(request.user, pk).pk)
        except BookingError as exc:
            return failure(exc)
        return Response(_state(booking))


class HouseholderReportView(_Householder):
    @extend_schema(request=ReportBodySerializer, responses={201: ReportReceiptSerializer})
    def post(self, request, pk):
        try:
            return _report(request.user, bookings.offer_booking(request.user, pk).pk, request)
        except BookingError as exc:
            return failure(exc)


class HouseholderReviewView(_Householder):
    @extend_schema(responses=ReviewStateSerializer)
    def get(self, request, pk):
        try:
            return _review_state(request.user, bookings.offer_booking(request.user, pk).pk)
        except BookingError as exc:
            return failure(exc)

    @extend_schema(request=ReviewBodySerializer, responses={201: ReviewStateSerializer})
    def post(self, request, pk):
        try:
            return _submit_review(request.user, bookings.offer_booking(request.user, pk).pk, request)
        except BookingError as exc:
            return failure(exc)
