from datetime import timedelta

from django import forms
from django.conf import settings
from django.contrib import admin
from django.urls import path, reverse
from django.utils import timezone
from django.utils.cache import patch_cache_control

from apps.accounts.phones import InvalidPhone, normalise
from apps.audit.services import record as audit
from apps.verification.services.encryption import decrypt_text

from . import console_views
from .models import Application, Booking, Payment, PaymentMethod
from .services import payments


class ReadOnlyAdmin(admin.ModelAdmin):
    """Staff look at applications and bookings; nothing is edited here."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Application)
class ApplicationAdmin(ReadOnlyAdmin):
    # The jobber's message is free text: it is shown on the detail page only, never in the list.
    list_display = ("created_at", "offer_category", "jobber_phone", "status")
    list_filter = ("status",)
    search_fields = ("jobber__phone",)
    ordering = ("-created_at",)
    list_select_related = ("offer", "jobber")
    fields = ("offer", "jobber", "status", "message", "created_at", "decided_at")
    readonly_fields = fields

    @admin.display(description="offre")
    def offer_category(self, obj):
        return obj.offer.category_name

    @admin.display(description="jobber")
    def jobber_phone(self, obj):
        return obj.jobber.phone


@admin.register(Booking)
class BookingAdmin(ReadOnlyAdmin):
    list_display = ("created_at", "category_name", "starts_at", "jobber_phone", "status")
    list_filter = ("status",)
    search_fields = ("jobber__phone", "householder__phone")
    ordering = ("-created_at",)
    list_select_related = ("jobber",)
    fields = (
        "offer",
        "application",
        "householder",
        "jobber",
        "status",
        "category_name",
        "starts_at",
        "duration_minutes",
        "pay_xof",
        "commune",
        "quartier",
        "accepted_at",
    )
    readonly_fields = fields

    @admin.display(description="jobber")
    def jobber_phone(self, obj):
        return obj.jobber.phone


class PaymentMethodForm(forms.ModelForm):
    class Meta:
        model = PaymentMethod
        fields = ["provider", "number", "account_name", "active", "position"]

    def clean_number(self):
        raw = (self.cleaned_data.get("number") or "").strip()
        if not raw:
            return ""
        try:
            return normalise(raw)
        except InvalidPhone as exc:
            raise forms.ValidationError("Numéro invalide.") from exc

    def clean(self):
        data = super().clean()
        if data.get("active") and not data.get("number"):
            raise forms.ValidationError("Un moyen de paiement actif doit avoir un numéro.")
        return data


@admin.register(PaymentMethod)
class PaymentMethodAdmin(admin.ModelAdmin):
    """Where householders pay. With no active method, nobody can apply or be accepted."""

    form = PaymentMethodForm
    list_display = ("provider", "number", "account_name", "active", "position")
    list_editable = ()
    ordering = ("position", "provider")

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        audit(
            request.user,
            "bookings.payment_method.change",
            obj,
            provider=obj.provider,
            active=obj.active,
            number=obj.number,
        )


class PaymentQueueFilter(admin.SimpleListFilter):
    """What staff have to do: check a payment (default), make a refund, or look at everything."""

    title = "à faire"
    parameter_name = "file"

    def lookups(self, request, model_admin):
        return [("refund", "Remboursements à faire"), ("all", "Tous")]

    def choices(self, changelist):
        yield {
            "selected": self.value() is None,
            "query_string": changelist.get_query_string(remove=[self.parameter_name]),
            "display": "À vérifier",
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
        if self.value() == "refund":
            return queryset.filter(status=Payment.Status.REFUND_DUE)
        return queryset.filter(status=Payment.Status.SUBMITTED)


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    """Staff check each payment against the platform account's own history, then confirm or refuse."""

    change_form_template = "admin/bookings/payment_review.html"
    list_display = ("submitted_at", "category", "method", "amount_xof", "status", "late")
    list_filter = (PaymentQueueFilter,)
    ordering = ("submitted_at",)
    list_select_related = ("booking", "method")
    # The typed reference and the screenshot are shown on the review page only, never in the list.
    fields = ("booking", "method", "amount_xof", "fee_xof", "status", "submitted_at", "decided_at")
    readonly_fields = fields

    @admin.display(description="réservation")
    def category(self, obj):
        return obj.booking.category_name

    @admin.display(description="retard")
    def late(self, obj):
        waited = timezone.now() - obj.submitted_at
        if obj.status == Payment.Status.SUBMITTED and waited > timedelta(
            hours=settings.PAYMENT_REVIEW_LATE_HOURS
        ):
            return "En retard"
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
            path("<uuid:pk>/confirm/", wrap(console_views.confirm_payment), name="bookings_payment_confirm"),
            path("<uuid:pk>/refuse/", wrap(console_views.refuse_payment), name="bookings_payment_refuse"),
            path("<uuid:pk>/refund/", wrap(console_views.record_refund), name="bookings_payment_refund"),
            path("<uuid:pk>/proof/", wrap(console_views.proof_image), name="bookings_payment_proof"),
        ]
        return custom + super().get_urls()

    def change_view(self, request, object_id, form_url="", extra_context=None):
        record = self.get_object(request, object_id)
        context = dict(extra_context or {})
        if record is not None and request.method == "GET" and self.has_view_permission(request, record):
            audit(request.user, "booking.payment.view", record, booking=str(record.booking_id))
            context.update(
                category=record.booking.category_name,
                starts_at=record.booking.starts_at,
                amount=record.amount_xof,
                fee=record.fee_xof,
                method=record.method.get_provider_display(),
                method_number=record.method.number,
                reference=decrypt_text(record.reference),
                seen_before=payments.proof_seen_before(record),
                proof_url=reverse("admin:bookings_payment_proof", args=[record.pk]),
                can_decide=record.status == Payment.Status.SUBMITTED,
                refund_due=record.status == Payment.Status.REFUND_DUE,
            )
        response = super().change_view(request, object_id, form_url, context)
        # The page shows a reference: it must never be cached.
        patch_cache_control(response, no_store=True)
        return response
