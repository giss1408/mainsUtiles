from django import forms
from django.contrib import admin, messages
from django.core.exceptions import PermissionDenied, ValidationError
from django.http import HttpResponseNotAllowed
from django.urls import path, reverse
from django.utils.cache import patch_cache_control

from apps.accounts.api.errors import MESSAGES

from .models import ModerationTerm, Offer, OfferCategory
from .services import moderation
from .services.moderation import ModerationError

FLAG_TEXT = {
    "pay_high": "Rémunération très au-dessus de la catégorie.",
    "pay_low": "Rémunération en dessous de la catégorie.",
    "contact_details": "Numéro de téléphone ou e-mail dans la précision.",
    "appearance": "Mention de l'âge, du genre ou de l'apparence.",
    "travel": "Mention de voyage, de logement ou de l'étranger.",
    "empty_home": "Indique que le domicile sera vide.",
    "off_platform": "Propose un contact hors de l'application.",
    "first_offer": "Première offre de ce compte.",
}


def _change_url(offer) -> str:
    return reverse("admin:listings_offer_change", args=[offer.pk])


class OfferQueueFilter(admin.SimpleListFilter):
    title = "état"
    parameter_name = "etat"

    def lookups(self, request, model_admin):
        return [("all", "Toutes"), *Offer.Status.choices]

    def choices(self, changelist):
        yield {
            "selected": self.value() is None,
            "query_string": changelist.get_query_string(remove=[self.parameter_name]),
            "display": "À modérer",
        }
        for lookup, title in self.lookup_choices:
            yield {
                "selected": self.value() == lookup,
                "query_string": changelist.get_query_string({self.parameter_name: lookup}),
                "display": title,
            }

    def queryset(self, request, queryset):
        if self.value() is None:
            return queryset.filter(status=Offer.Status.IN_REVIEW)
        if self.value() == "all":
            return queryset
        return queryset.filter(status=self.value())


@admin.register(Offer)
class OfferAdmin(admin.ModelAdmin):
    """The moderation queue. Offers are never edited here: publishing and refusing are actions."""

    change_form_template = "admin/listings/offer_review.html"
    list_display = (
        "sent_at",
        "author_phone",
        "category_name",
        "starts_at",
        "pay_xof",
        "commune",
        "status",
        "flags_display",
    )
    list_filter = (OfferQueueFilter,)
    ordering = ("sent_at",)
    list_select_related = ("author",)
    fields = (
        "author",
        "category_name",
        "duties",
        "starts_at",
        "duration_minutes",
        "pay_xof",
        "note",
        "commune",
        "quartier",
        "status",
        "reason",
        "sent_at",
        "published_at",
    )
    readonly_fields = fields

    @admin.display(description="téléphone")
    def author_phone(self, obj):
        return obj.author.phone

    @admin.display(description="signalements")
    def flags_display(self, obj):
        return ", ".join(obj.flags)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def get_urls(self):
        wrap = self.admin_site.admin_view
        custom = [
            path("<uuid:pk>/publish/", wrap(self.publish_view), name="listings_offer_publish"),
            path("<uuid:pk>/refuse/", wrap(self.refuse_view), name="listings_offer_refuse"),
        ]
        return custom + super().get_urls()

    def change_view(self, request, object_id, form_url="", extra_context=None):
        offer = self.get_object(request, object_id)
        context = dict(extra_context or {})
        if offer is not None and request.method == "GET" and self.has_view_permission(request, offer):
            context.update(
                reviewable=offer.status == Offer.Status.IN_REVIEW,
                flag_texts=[FLAG_TEXT.get(flag, flag) for flag in offer.flags],
            )
        response = super().change_view(request, object_id, form_url, context)
        patch_cache_control(response, no_store=True)
        return response

    def publish_view(self, request, pk):
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        return self._decide(
            request, pk, lambda offer: moderation.publish(offer, staff=request.user), "Offre publiée."
        )

    def refuse_view(self, request, pk):
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        reason = request.POST.get("reason", "")
        return self._decide(
            request,
            pk,
            lambda offer: moderation.refuse(offer, staff=request.user, reason=reason),
            "Offre refusée.",
        )

    def _decide(self, request, pk, action, success):
        offer = self.get_object(request, str(pk))
        if offer is None:
            raise PermissionDenied
        try:
            action(offer)
        except ModerationError as exc:
            if exc.code == "forbidden":
                raise PermissionDenied from exc
            messages.error(request, MESSAGES.get(exc.code, exc.code))
        else:
            messages.success(request, success)
        return _redirect(offer)


def _redirect(offer):
    from django.shortcuts import redirect

    return redirect(_change_url(offer))


class CategoryForm(forms.ModelForm):
    """Duties and durations are entered one per line; the model validates the rest."""

    duties = forms.CharField(
        label="tâches",
        widget=forms.Textarea(attrs={"rows": 6}),
        help_text="Une tâche par ligne.",
    )
    durations_minutes = forms.CharField(
        label="durées (minutes)",
        widget=forms.Textarea(attrs={"rows": 3}),
        help_text="Une durée par ligne, en minutes (120 = 2 h).",
    )

    class Meta:
        model = OfferCategory
        fields = [
            "name",
            "duties",
            "durations_minutes",
            "suggested_pay_min",
            "suggested_pay_max",
            "active",
            "position",
        ]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.instance and self.instance.pk:
            self.initial["duties"] = "\n".join(self.instance.duties)
            self.initial["durations_minutes"] = "\n".join(str(m) for m in self.instance.durations_minutes)

    def clean_duties(self):
        lines = [line.strip() for line in self.cleaned_data["duties"].splitlines() if line.strip()]
        if not lines:
            raise ValidationError("Indiquez au moins une tâche.")
        return lines

    def clean_durations_minutes(self):
        values = []
        for line in self.cleaned_data["durations_minutes"].splitlines():
            if not line.strip():
                continue
            try:
                values.append(int(line.strip()))
            except ValueError as exc:
                raise ValidationError(f"« {line.strip()} » n'est pas une durée en minutes.") from exc
        if not values:
            raise ValidationError("Indiquez au moins une durée.")
        return values

    def _post_clean(self):
        super()._post_clean()
        if self.errors:
            return
        try:
            self.instance.full_clean(exclude=["name", "position", "active"])
        except ValidationError as exc:
            self.add_error(None, exc)


@admin.register(OfferCategory)
class OfferCategoryAdmin(admin.ModelAdmin):
    form = CategoryForm
    list_display = ("name", "active", "position", "suggested_pay_min", "suggested_pay_max")
    list_editable = ("active", "position")
    ordering = ("position", "name")

    def has_add_permission(self, request):
        return request.user.has_perm("listings.add_offercategory")


@admin.register(ModerationTerm)
class ModerationTermAdmin(admin.ModelAdmin):
    list_display = ("text", "kind")
    list_filter = ("kind",)
    search_fields = ("text",)
    ordering = ("kind", "text")
