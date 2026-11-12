import uuid
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class OfferCategory(models.Model):
    """A kind of mini-job, with the choices a householder is offered. Edited by staff."""

    name = models.CharField("nom", max_length=80, unique=True)
    duties = models.JSONField("tâches", default=list, help_text="Les tâches que le particulier peut cocher.")
    durations_minutes = models.JSONField("durées (minutes)", default=list)
    suggested_pay_min = models.PositiveIntegerField("rémunération conseillée, minimum (FCFA)")
    suggested_pay_max = models.PositiveIntegerField("rémunération conseillée, maximum (FCFA)")
    active = models.BooleanField("active", default=True)
    position = models.PositiveIntegerField("ordre", default=0)

    class Meta:
        verbose_name = "catégorie d'offre"
        verbose_name_plural = "catégories d'offres"
        ordering = ["position", "name"]

    def __str__(self):
        return self.name

    def clean(self):
        errors = {}
        duties = self.duties
        if (
            not isinstance(duties, list)
            or not duties
            or not all(isinstance(duty, str) and duty.strip() for duty in duties)
        ):
            errors["duties"] = "Indiquez au moins une tâche, sans ligne vide."
        durations = self.durations_minutes
        if (
            not isinstance(durations, list)
            or not durations
            or not all(
                isinstance(minutes, int) and not isinstance(minutes, bool) and minutes > 0
                for minutes in durations
            )
        ):
            errors["durations_minutes"] = "Indiquez au moins une durée, en minutes."
        if (
            self.suggested_pay_min is not None
            and self.suggested_pay_max is not None
            and self.suggested_pay_min > self.suggested_pay_max
        ):
            errors["suggested_pay_max"] = "Le maximum doit être supérieur ou égal au minimum."
        if errors:
            raise ValidationError(errors)


class ModerationTerm(models.Model):
    """A word or phrase that sends an offer to a staff member. Edited by staff."""

    class Kind(models.TextChoices):
        APPEARANCE = "appearance", "Âge, genre ou apparence"
        TRAVEL = "travel", "Voyage, logement, étranger"
        EMPTY_HOME = "empty_home", "Domicile vide"
        OFF_PLATFORM = "off_platform", "Contact hors de l'application"

    text = models.CharField("terme", max_length=80)
    kind = models.CharField("type", max_length=20, choices=Kind.choices)

    class Meta:
        verbose_name = "terme de modération"
        verbose_name_plural = "termes de modération"
        ordering = ["kind", "text"]
        constraints = [models.UniqueConstraint(fields=["text", "kind"], name="unique_term_per_kind")]

    def __str__(self):
        return f"{self.text} ({self.get_kind_display()})"


class Offer(models.Model):
    """A mini-job offered by a householder at their confirmed address."""

    class Status(models.TextChoices):
        DRAFT = "draft", "Brouillon"
        IN_REVIEW = "in_review", "En cours de vérification"
        PUBLISHED = "published", "Publiée"
        REFUSED = "refused", "Refusée"
        WITHDRAWN = "withdrawn", "Retirée"
        CLOSED = "closed", "Terminée"

    # Offers that count toward a householder's limit and that jobbers may come to see.
    OPEN_STATUSES = (Status.IN_REVIEW.value, Status.PUBLISHED.value)

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="offers")
    category = models.ForeignKey(OfferCategory, on_delete=models.PROTECT, related_name="+")
    # Copied when the offer is sent, so later catalogue edits do not rewrite it.
    category_name = models.CharField(max_length=80, blank=True)
    duties = models.JSONField(default=list)
    starts_at = models.DateTimeField()
    duration_minutes = models.PositiveIntegerField()
    pay_xof = models.PositiveIntegerField()
    note = models.TextField(blank=True)
    # The householder's confirmed commune and quartier, copied when the offer is sent.
    commune = models.CharField(max_length=60, blank=True)
    quartier = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT)
    flags = models.JSONField(default=list, blank=True)
    reason = models.TextField(blank=True)
    moderated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    moderated_at = models.DateTimeField(null=True, blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)
    published_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "offre"
        verbose_name_plural = "offres"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status", "starts_at"]),
            models.Index(fields=["author", "created_at"]),
        ]
        permissions = [("moderate_offer", "Peut publier ou refuser une offre")]

    def __str__(self):
        return f"{self.category_name or self.category.name} ({self.get_status_display()})"

    @property
    def ends_at(self):
        return self.starts_at + timedelta(minutes=self.duration_minutes)
