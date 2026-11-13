"""Jobber endpoints: the published offers. Rules stay in the services."""

from django.conf import settings
from django.core.paginator import Paginator
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.bookings.services import applications
from apps.listings.services import offers

from .jobber_serializers import PublicOfferSerializer

PAGE_SIZE = 20


class IsJobberRole(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.role == "jobber")


class OffersView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(responses=PublicOfferSerializer(many=True))
    def get(self, request):
        communes = list(settings.SERVICE_COMMUNES)
        commune = request.query_params.get("commune", "").strip()
        if commune and commune not in communes:
            return error_response("commune_invalid")
        visible = offers.visible_to_jobbers()
        if commune:
            visible = visible.filter(commune=commune)
        page_number = request.query_params.get("page", "1")
        page = Paginator(visible, PAGE_SIZE).get_page(page_number)
        return Response(
            {
                "count": page.paginator.count,
                "next": page.next_page_number() if page.has_next() else None,
                "previous": page.previous_page_number() if page.has_previous() else None,
                "results": PublicOfferSerializer(page.object_list, many=True).data,
                "communes": communes,
            }
        )


class OfferView(APIView):
    permission_classes = [IsJobberRole]

    @extend_schema(responses=PublicOfferSerializer)
    def get(self, request, pk):
        offer = get_object_or_404(offers.visible_to_jobbers().select_related("author"), pk=pk)
        mine = offer.applications.filter(jobber=request.user, status__in=("pending", "accepted")).first()
        return Response(
            {
                **PublicOfferSerializer(offer).data,
                # A trust line, never a name, a phone or an id.
                "householder": applications.householder_trust(offer.author),
                "my_application": {"id": str(mine.pk), "status": mine.status} if mine else None,
            }
        )
