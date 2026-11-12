from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from django.urls import path

from . import console_views
from .models import DeviceEnrolmentRequest, StaffDevice, User
from .services import staff_auth

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


@admin.register(StaffDevice)
class StaffDeviceAdmin(admin.ModelAdmin):
    """Staff phones waiting for activation. Administrators only; changes go through the service."""

    list_display = ("user", "model", "platform", "status", "enrolled_at", "revoked_at")
    list_filter = ("status",)
    search_fields = ("user__username",)
    ordering = ("-enrolled_at",)
    fields = ("user", "model", "platform", "status", "enrolled_at", "revoked_at")
    readonly_fields = fields
    actions = ("activate", "revoke")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(user__role="staff").select_related("user")

    def has_module_permission(self, request):
        return request.user.is_active and request.user.is_superuser

    def has_view_permission(self, request, obj=None):
        return request.user.is_active and request.user.is_superuser

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def _apply(self, request, queryset, service_function, done_message):
        for device in queryset:
            try:
                service_function(device, admin=request.user)
            except staff_auth.AuthError:
                self.message_user(
                    request, f"{device.user} — {device} : action impossible dans cet état.", messages.ERROR
                )
            else:
                self.message_user(request, f"{device.user} — {device.model} : {done_message}")

    @admin.action(description="Activer")
    def activate(self, request, queryset):
        self._apply(request, queryset, staff_auth.activate_device, "appareil activé.")

    @admin.action(description="Révoquer")
    def revoke(self, request, queryset):
        self._apply(request, queryset, staff_auth.revoke_device, "appareil révoqué.")
