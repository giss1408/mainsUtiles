"""Householder offer endpoints. Rules stay in the services; views only translate HTTP."""

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.api.errors import error_response
from apps.accounts.permissions import IsHouseholder
from apps.listings.models import Offer
from apps.listings.services import catalogue, offers
from apps.listings.services.offers import OfferError
from apps.verification.services.tiers import householder_tier

from .serializers import (
    MyOfferSerializer,
    OfferCategorySerializer,
    OfferDraftSerializer,
    OfferPatchSerializer,
    offer_limits,
)

ALREADY_SENT = "Cette offre a déjà été envoyée."
NOT_FOUND = "Offre introuvable."


def _failure(exc: OfferError):
    if exc.code == "forbidden":
        # Do not reveal that someone else's offer exists.
        return Response({"error": "forbidden", "message": NOT_FOUND}, status=404)
    if exc.code == "invalid_state":
        return Response({"error": exc.code, "message": ALREADY_SENT}, status=409)
    return error_response(exc.code)


def _mine(request, pk) -> Offer:
    """The caller's own offer, or 404: an offer of anyone else is not visible."""
    return get_object_or_404(Offer, pk=pk, author=request.user)


class _HouseholderView(APIView):
    permission_classes = [IsHouseholder]


class CategoriesView(_HouseholderView):
    @extend_schema(responses=OfferCategorySerializer(many=True))
    def get(self, request):
        return Response(
            {
                "categories": OfferCategorySerializer(catalogue.active_categories(), many=True).data,
                "limits": offer_limits(),
            }
        )


class MyOffersView(_HouseholderView):
    @extend_schema(responses=MyOfferSerializer(many=True))
    def get(self, request):
        from django.conf import settings

        mine = Offer.objects.filter(author=request.user).order_by("-created_at")
        return Response(
            {
                "can_publish": householder_tier(request.user) == "H1",
                "review_hours": settings.OFFER_REVIEW_HOURS,
                "offers": MyOfferSerializer(mine, many=True).data,
            }
        )

    @extend_schema(request=OfferDraftSerializer, responses=MyOfferSerializer)
    def post(self, request):
        serializer = OfferDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            offer = offers.create_draft(request.user, **serializer.validated_data)
        except OfferError as exc:
            return _failure(exc)
        return Response(MyOfferSerializer(offer).data, status=status.HTTP_201_CREATED)


class MyOfferView(_HouseholderView):
    @extend_schema(request=OfferPatchSerializer, responses=MyOfferSerializer)
    def patch(self, request, pk):
        serializer = OfferPatchSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        offer = _mine(request, pk)
        try:
            updated = offers.update_draft(offer, user=request.user, **serializer.validated_data)
        except OfferError as exc:
            return _failure(exc)
        return Response(MyOfferSerializer(updated).data)

    def delete(self, request, pk):
        offer = _mine(request, pk)
        try:
            offers.delete_draft(offer, user=request.user)
        except OfferError as exc:
            return _failure(exc)
        return Response(status=status.HTTP_204_NO_CONTENT)


class _OfferAction(_HouseholderView):
    action = None

    def post(self, request, pk):
        offer = _mine(request, pk)
        try:
            result = getattr(offers, self.action)(offer, user=request.user)
        except OfferError as exc:
            return _failure(exc)
        code = status.HTTP_201_CREATED if self.action == "copy_as_draft" else status.HTTP_200_OK
        return Response(MyOfferSerializer(result).data, status=code)


class SendView(_OfferAction):
    action = "send"


class WithdrawView(_OfferAction):
    action = "withdraw"


class CopyView(_OfferAction):
    action = "copy_as_draft"
