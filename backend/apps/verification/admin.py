from django.contrib import admin
from django.core.exceptions import PermissionDenied
from django.urls import path, reverse
from django.utils.cache import patch_cache_control

from . import console_views
from .models import UNDECIDED, AddressProof, HomeLocation, IdentityVerification, Status
from .services import review
from .services.encryption import decrypt_text
from .services.submissions import VerificationError, location_coordinates
from .services.tiers import current_record

FLAG_TEXT = {"photo_reused": "Cette photo a déjà été envoyée par un autre compte."}


class TodoFilter(admin.SimpleListFilter):
    """Shows what is waiting for a decision unless staff ask for something else."""

    title = "état"
    parameter_name = "etat"

    def lookups(self, request, model_admin):
        return [("all", "Toutes"), *[(s.value, s.label) for s in Status]]

    def choices(self, changelist):
        yield {
            "selected": self.value() is None,
            "query_string": changelist.get_query_string(remove=[self.parameter_name]),
            "display": "À traiter",
        }
        for lookup, title in self.lookup_choices:
            yield {
                "selected": self.value() == lookup,
                "query_string": changelist.get_query_string({self.parameter_name: lookup}),
                "display": title,
            }

    def queryset(self, request, queryset):
        if self.value() is None:
            return queryset.filter(status__in=UNDECIDED)
        if self.value() == "all":
            return queryset
        return queryset.filter(status=self.value())


class ReviewAdmin(admin.ModelAdmin):
    """A review queue. Records are never edited here: every change goes through an action."""

    list_display = ("created_at", "phone", "document_type", "status", "flags")
    list_filter = (TodoFilter,)
    search_fields = ("user__phone",)
    ordering = ("created_at",)
    # Encrypted columns are deliberately left out.
    fields = ("user", "document_type", "status", "reason", "reviewed_by", "reviewed_at", "created_at")
    readonly_fields = fields
    list_select_related = ("user",)

    @admin.display(description="téléphone", ordering="user__phone")
    def phone(self, obj):
        return obj.user.phone

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def review_context(self, request, record) -> dict:
        raise NotImplementedError

    def change_view(self, request, object_id, form_url="", extra_context=None):
        record = self.get_object(request, object_id)
        context = dict(extra_context or {})
        if record is not None and request.method == "GET" and self.has_view_permission(request, record):
            try:
                review.open_for_review(record, staff=request.user)
                review.record_view(record, staff=request.user)
            except VerificationError as exc:
                raise PermissionDenied from exc
            context.update(
                undecided=record.status in UNDECIDED,
                flag_texts=[FLAG_TEXT.get(flag, flag) for flag in record.flags],
                **self.review_context(request, record),
            )
        response = super().change_view(request, object_id, form_url, context)
        # The page shows names and positions: it must never be cached.
        patch_cache_control(response, no_store=True)
        return response


@admin.register(IdentityVerification)
class IdentityVerificationAdmin(ReviewAdmin):
    change_form_template = "admin/verification/identity_review.html"

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path(
                "<uuid:pk>/confirm/",
                wrap(console_views.confirm_identity),
                name="verification_identity_confirm",
            ),
            path(
                "<uuid:pk>/refuse/", wrap(console_views.refuse_identity), name="verification_identity_refuse"
            ),
            path(
                "<uuid:pk>/photo/<uuid:photo_id>/",
                wrap(console_views.identity_photo),
                name="verification_identity_photo",
            ),
        ]
        return custom + super().get_urls()

    def review_context(self, request, record) -> dict:
        return {
            "photos": [
                (
                    photo.get_kind_display(),
                    reverse("admin:verification_identity_photo", args=[record.pk, photo.pk]),
                )
                for photo in (record.front, record.back, record.selfie)
            ],
        }


@admin.register(AddressProof)
class AddressProofAdmin(ReviewAdmin):
    change_form_template = "admin/verification/address_review.html"
    list_display = ("created_at", "phone", "document_type", "commune", "quartier", "status", "flags")
    fields = ("user", "document_type", "commune", "quartier", *ReviewAdmin.fields[2:], "expires_at")
    readonly_fields = fields

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path(
                "<uuid:pk>/confirm/", wrap(console_views.confirm_address), name="verification_address_confirm"
            ),
            path("<uuid:pk>/refuse/", wrap(console_views.refuse_address), name="verification_address_refuse"),
            path(
                "<uuid:pk>/photo/<uuid:photo_id>/",
                wrap(console_views.address_photo),
                name="verification_address_photo",
            ),
        ]
        return custom + super().get_urls()

    def review_context(self, request, record) -> dict:
        identity = current_record(IdentityVerification, record.user)
        confirmed = identity is not None and identity.status == Status.CONFIRMED
        location = current_record(HomeLocation, record.user)
        position = None
        if location is not None and location.status in (*UNDECIDED, Status.CONFIRMED):
            lat, lng = location_coordinates(location)
            position = {
                "id": location.pk if location.status in UNDECIDED else "",
                # Plain text: the French locale would print decimal commas.
                "lat": str(lat),
                "lng": str(lng),
                "accuracy_m": location.accuracy_m,
                "mock": location.mock_location,
                "map_url": f"https://www.openstreetmap.org/?mlat={lat}&mlon={lng}#map=17/{lat}/{lng}",
            }
        return {
            "photo_url": reverse("admin:verification_address_photo", args=[record.pk, record.photo.pk]),
            "identity_name": decrypt_text(identity.full_name) if confirmed else None,
            "position": position,
        }
