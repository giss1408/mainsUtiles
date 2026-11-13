from django import forms
from django.contrib import admin
from django.core.exceptions import PermissionDenied, ValidationError
from django.urls import path, reverse
from django.utils.cache import patch_cache_control

from apps.audit.services import record as audit

from . import console_views
from .models import (
    UNDECIDED,
    AddressProof,
    BriefingCard,
    ContactStatus,
    Guarantor,
    HomeLocation,
    IdentityVerification,
    Status,
    TrustedContact,
)
from .services import contacts, review
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


@admin.register(Guarantor)
class GuarantorAdmin(ReviewAdmin):
    change_form_template = "admin/verification/guarantor_review.html"
    list_display = ("created_at", "phone", "document_type", "relationship", "status", "flags")
    fields = (
        "user",
        "document_type",
        "relationship",
        *ReviewAdmin.fields[2:],
        "contacted_at",
        "expires_at",
    )
    readonly_fields = fields

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path(
                "<uuid:pk>/call/",
                wrap(console_views.record_guarantor_call),
                name="verification_guarantor_call",
            ),
            path(
                "<uuid:pk>/confirm/",
                wrap(console_views.confirm_guarantor),
                name="verification_guarantor_confirm",
            ),
            path(
                "<uuid:pk>/refuse/",
                wrap(console_views.refuse_guarantor),
                name="verification_guarantor_refuse",
            ),
            path(
                "<uuid:pk>/photo/<uuid:photo_id>/",
                wrap(console_views.guarantor_photo),
                name="verification_guarantor_photo",
            ),
        ]
        return custom + super().get_urls()

    def review_context(self, request, record) -> dict:
        identity = current_record(IdentityVerification, record.user)
        confirmed = identity is not None and identity.status == Status.CONFIRMED
        return {
            "photo_url": reverse("admin:verification_guarantor_photo", args=[record.pk, record.photo.pk]),
            "identity_name": decrypt_text(identity.full_name) if confirmed else None,
            "guarantor_name": decrypt_text(record.guarantor_name),
            "guarantor_phone": decrypt_text(record.guarantor_phone),
            "relationship_label": record.get_relationship_display(),
        }


class ContactQueueFilter(admin.SimpleListFilter):
    """What staff have to do: send a code (default), warn an old number, or everything."""

    title = "à faire"
    parameter_name = "file"

    def lookups(self, request, model_admin):
        return [("notice", "À prévenir"), ("all", "Toutes")]

    def choices(self, changelist):
        yield {
            "selected": self.value() is None,
            "query_string": changelist.get_query_string(remove=[self.parameter_name]),
            "display": "À envoyer",
        }
        for lookup, title in self.lookup_choices:
            yield {
                "selected": self.value() == lookup,
                "query_string": changelist.get_query_string({self.parameter_name: lookup}),
                "display": title,
            }

    def queryset(self, request, queryset):
        if self.value() == "all":
            return queryset
        if self.value() == "notice":
            return queryset.filter(pk__in=contacts.notice_queue().values("pk"))
        return queryset.filter(pk__in=contacts.send_queue().values("pk"))


@admin.register(TrustedContact)
class TrustedContactAdmin(admin.ModelAdmin):
    """Staff send each trusted contact a code on WhatsApp. Nothing is edited here."""

    change_form_template = "admin/verification/trustedcontact_review.html"
    list_display = ("created_at", "jobber_phone", "relationship", "status", "state")
    list_filter = (ContactQueueFilter,)
    search_fields = ("user__phone",)
    ordering = ("created_at",)
    # Encrypted columns are deliberately left out: the name is shown on the review page only.
    fields = ("user", "relationship", "status", "created_at", "code_sent_at", "confirmed_at")
    readonly_fields = fields
    list_select_related = ("user",)

    @admin.display(description="téléphone du jeune", ordering="user__phone")
    def jobber_phone(self, obj):
        return obj.user.phone

    @admin.display(description="à faire")
    def state(self, obj):
        if contacts.awaiting_code(obj):
            return "Envoyer le code"
        if obj.status == ContactStatus.CONFIRMED and obj.old_notified_at is None:
            return "Confirmé"
        return ""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path(
                "<uuid:pk>/send/",
                wrap(console_views.send_contact_code),
                name="verification_trustedcontact_send",
            ),
            path(
                "<uuid:pk>/notice/",
                wrap(console_views.notify_old_contact),
                name="verification_trustedcontact_notice",
            ),
        ]
        return custom + super().get_urls()

    def change_view(self, request, object_id, form_url="", extra_context=None):
        record = self.get_object(request, object_id)
        context = dict(extra_context or {})
        if record is not None and request.method == "GET" and self.has_view_permission(request, record):
            audit(request.user, "verification.contact.view", record)
            identity = current_record(IdentityVerification, record.user)
            confirmed = identity is not None and identity.status == Status.CONFIRMED
            replacement_confirmed = TrustedContact.objects.filter(
                replaces=record, status=ContactStatus.CONFIRMED
            ).exists()
            context.update(
                contact_name=decrypt_text(record.name),
                relationship_label=record.get_relationship_display(),
                identity_name=decrypt_text(identity.full_name) if confirmed else None,
                can_send=record.status == ContactStatus.PENDING,
                awaiting=contacts.awaiting_code(record),
                needs_notice=(
                    record.status == ContactStatus.CONFIRMED
                    and record.old_notified_at is None
                    and replacement_confirmed
                ),
                replaces_a_contact=record.replaces_id is not None,
            )
        response = super().change_view(request, object_id, form_url, context)
        # The page shows a name: it must never be cached.
        patch_cache_control(response, no_store=True)
        return response


class BriefingCardForm(forms.ModelForm):
    """Choices are typed one per line; the right answer is the number of its line, from 1."""

    choices = forms.CharField(
        label="choix",
        widget=forms.Textarea(attrs={"rows": 4}),
        help_text="Un choix par ligne (de 2 à 4).",
    )
    correct_index = forms.IntegerField(
        label="bonne réponse (numéro de la ligne, à partir de 1)",
        error_messages={"invalid": "Entrez un nombre entier."},
    )

    class Meta:
        model = BriefingCard
        fields = [
            "title",
            "body",
            "question",
            "choices",
            "correct_index",
            "explanation",
            "position",
            "active",
        ]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if not self.instance._state.adding:
            self.initial["choices"] = "\n".join(self.instance.choices)
            self.initial["correct_index"] = self.instance.correct_index + 1

    def clean_choices(self):
        return [line.strip() for line in self.cleaned_data["choices"].splitlines() if line.strip()]

    def clean_correct_index(self):
        number = self.cleaned_data["correct_index"]
        if number < 1:
            raise ValidationError("La bonne réponse doit être l'un des choix.")
        return number - 1


@admin.register(BriefingCard)
class BriefingCardAdmin(admin.ModelAdmin):
    """The safety briefing, edited by staff. The first cards are placeholders."""

    form = BriefingCardForm
    list_display = ("title", "position", "active")
    list_display_links = ("title",)
    list_editable = ("position", "active")
    ordering = ("position", "title")
