from django import forms
from django.contrib import admin

from apps.accounts.phones import InvalidPhone, normalise
from apps.audit.services import record as audit

from .models import Application, Booking, PaymentMethod


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
