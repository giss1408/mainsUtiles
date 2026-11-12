"""Staff app endpoints. Rules stay in the services; views only translate HTTP."""

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Device, DeviceEnrolmentRequest
from apps.accounts.permissions import HasStaffPermission, IsStaffMember
from apps.accounts.services import enrolment, staff_auth
from apps.providers import registry

from .errors import error_response
from .serializers import TokenPairSerializer
from .staff_serializers import (
    EnrolmentDetailSerializer,
    EnrolmentItemSerializer,
    QueueFilterSerializer,
    ReasonSerializer,
    StaffDeviceSerializer,
    StaffDeviceStatusSerializer,
    StaffLoginSerializer,
    StaffMeSerializer,
    WhatsAppUrlSerializer,
)
from .views import PublicView, auth_error

CanReview = HasStaffPermission("accounts.review_enrolment")
CanSend = HasStaffPermission("accounts.send_enrolment_code")


class StaffDeviceView(PublicView):
    @extend_schema(request=StaffDeviceSerializer, responses=StaffDeviceStatusSerializer)
    def post(self, request):
        serializer = StaffDeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        known = Device.objects.filter(pk=serializer.validated_data["device_id"]).exists()
        try:
            device = staff_auth.register_device(**serializer.validated_data)
        except staff_auth.AuthError as exc:
            return auth_error(exc)
        return Response({"status": device.status}, status=200 if known else 201)


class StaffLoginView(PublicView):
    @extend_schema(request=StaffLoginSerializer, responses=TokenPairSerializer)
    def post(self, request):
        serializer = StaffLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            pair = staff_auth.login(
                username=data["username"],
                password=data["password"],
                device_id=data["device_id"],
                nonce=data["nonce"],
                signature_b64=data["signature"],
            )
        except staff_auth.AuthError as exc:
            return auth_error(exc)
        return Response({"access": pair.access, "refresh": pair.refresh})


class StaffMeView(APIView):
    permission_classes = [IsStaffMember]

    @extend_schema(responses=StaffMeSerializer)
    def get(self, request):
        codenames = sorted(perm.split(".", 1)[1] for perm in request.user.get_all_permissions())
        return Response(
            {"id": str(request.user.pk), "username": request.user.username, "permissions": codenames}
        )


class QueuePagination(PageNumberPagination):
    page_size = 20


class EnrolmentQueueView(APIView):
    permission_classes = [CanReview]

    @extend_schema(parameters=[QueueFilterSerializer], responses=EnrolmentItemSerializer(many=True))
    def get(self, request):
        filters = QueueFilterSerializer(data=request.query_params)
        filters.is_valid(raise_exception=True)
        rows = DeviceEnrolmentRequest.objects.filter(status=filters.validated_data["status"]).order_by(
            "created_at", "id"
        )
        paginator = QueuePagination()
        page = paginator.paginate_queryset(rows, request, view=self)
        return paginator.get_paginated_response(EnrolmentItemSerializer(page, many=True).data)


class EnrolmentDetailView(APIView):
    permission_classes = [CanReview]

    @extend_schema(responses=EnrolmentDetailSerializer)
    def get(self, request, id):
        return Response(EnrolmentDetailSerializer(get_object_or_404(DeviceEnrolmentRequest, pk=id)).data)


class _ActionView(APIView):
    permission_classes = [CanReview]

    def run(self, request, id, action):
        req = get_object_or_404(DeviceEnrolmentRequest, pk=id)
        try:
            action(req)
        except enrolment.EnrolmentError as exc:
            return error_response(exc.code)
        return Response(EnrolmentDetailSerializer(req).data)

    def reason(self, request) -> str:
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return serializer.validated_data["reason"]


class EnrolmentApproveView(_ActionView):
    @extend_schema(request=None, responses=EnrolmentDetailSerializer)
    def post(self, request, id):
        return self.run(request, id, lambda req: enrolment.approve(req, staff=request.user))


class EnrolmentRefuseView(_ActionView):
    @extend_schema(request=ReasonSerializer, responses=EnrolmentDetailSerializer)
    def post(self, request, id):
        reason = self.reason(request)
        return self.run(request, id, lambda req: enrolment.refuse(req, staff=request.user, reason=reason))


class EnrolmentHoldView(_ActionView):
    @extend_schema(request=ReasonSerializer, responses=EnrolmentDetailSerializer)
    def post(self, request, id):
        reason = self.reason(request)
        return self.run(request, id, lambda req: enrolment.hold(req, staff=request.user, reason=reason))


class EnrolmentSendView(APIView):
    permission_classes = [CanSend]

    @extend_schema(request=None, responses=WhatsAppUrlSerializer)
    def post(self, request, id):
        req = get_object_or_404(DeviceEnrolmentRequest, pk=id)
        try:
            code = enrolment.issue_code(req, staff=request.user)
        except enrolment.EnrolmentError as exc:
            return error_response(exc.code)
        link = registry.get_messaging().whatsapp_link(
            req.phone, enrolment.CONFIRMATION_MESSAGE.format(code=code)
        )
        # The link carries the confirmation number: it must never be cached.
        return Response({"whatsapp_url": link}, headers={"Cache-Control": "no-store"})
