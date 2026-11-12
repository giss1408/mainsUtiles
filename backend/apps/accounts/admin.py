from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from django.urls import path

from . import console_views
from .models import DeviceEnrolmentRequest, User

admin.site.site_header = "petitGombo — console"
admin.site.site_title = "petitGombo"
admin.site.index_title = "Opérations"


@admin.register(DeviceEnrolmentRequest)
class DeviceEnrolmentRequestAdmin(admin.ModelAdmin):
    """The enrolment queue. Rows are never edited here: every change goes through an action."""

    list_display = ("created_at", "phone", "role", "kind", "status", "flags", "integrity_verdict")
    list_filter = ("status", "kind", "role")
    search_fields = ("phone",)
    ordering = ("created_at",)
    # Hashes and tokens are deliberately left out.
    fields = (
        "phone",
        "role",
        "kind",
        "status",
        "reason",
        "flags",
        "device_model",
        "platform",
        "integrity_verdict",
        "approx_lat",
        "approx_lng",
        "ip_address",
        "created_at",
        "approved_by",
        "approved_at",
        "sent_by",
        "sent_at",
        "selfie_verified_at",
        "completed_at",
    )
    readonly_fields = fields

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path("<uuid:pk>/approve/", wrap(console_views.approve), name="accounts_enrolment_approve"),
            path("<uuid:pk>/refuse/", wrap(console_views.refuse), name="accounts_enrolment_refuse"),
            path("<uuid:pk>/hold/", wrap(console_views.hold), name="accounts_enrolment_hold"),
            path("<uuid:pk>/send/", wrap(console_views.send), name="accounts_enrolment_send"),
        ]
        return custom + super().get_urls()


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    """Staff accounts are managed here. App users are created only by enrolment."""

    list_display = ("username", "phone", "role", "is_staff", "is_active", "created_at")
    list_filter = ("role", "is_staff", "is_active", "groups")
    search_fields = ("username", "phone")
    ordering = ("-created_at",)
    readonly_fields = ("phone", "created_at", "last_login")
    fieldsets = (
        (None, {"fields": ("username", "password")}),
        ("Compte", {"fields": ("role", "phone", "is_active", "created_at", "last_login")}),
        ("Droits", {"fields": ("is_staff", "is_superuser", "groups", "user_permissions")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("username", "password1", "password2", "role", "is_staff")}),
    )
