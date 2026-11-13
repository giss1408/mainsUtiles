import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


class Application(models.Model):
    """A jobber asking to do an offer."""

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        ACCEPTED = "accepted", "Acceptée"
        DECLINED = "declined", "Refusée"
        WITHDRAWN = "withdrawn", "Retirée"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    offer = models.ForeignKey("listings.Offer", on_delete=models.PROTECT, related_name="applications")
    jobber = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    message = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    created_at = models.DateTimeField(auto_now_add=True)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "candidature"
        verbose_name_plural = "candidatures"
        ordering = ["created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["offer", "jobber"],
                condition=Q(status__in=("pending", "accepted")),
                name="one_live_application",
            )
        ]
        indexes = [models.Index(fields=["jobber", "status"])]

    def __str__(self):
        return f"{self.offer_id} / {self.get_status_display()}"


class Booking(models.Model):
    """A jobber chosen for an offer, with what was agreed copied from it."""

    class Status(models.TextChoices):
        ACCEPTED = "accepted", "Acceptée"
        CONFIRMED = "confirmed", "Confirmée"
        ADDRESS_RELEASED = "address_released", "Adresse communiquée"
        CHECKED_IN = "checked_in", "En cours"
        COMPLETION_PENDING = "completion_pending", "À confirmer"
        COMPLETED = "completed", "Terminée"
        CANCELLED = "cancelled", "Annulée"
        EXPIRED = "expired", "Expirée"
        DISPUTED = "disputed", "Litige"
        SAFETY_HOLD = "safety_hold", "Suspendue"

    # Every state in which the booking still occupies its offer and its jobber.
    LIVE = tuple(value for value in Status.values if value not in ("cancelled", "expired", "completed"))

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    offer = models.ForeignKey("listings.Offer", on_delete=models.PROTECT, related_name="bookings")
    application = models.OneToOneField(Application, on_delete=models.PROTECT, related_name="booking")
    householder = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    jobber = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    # Copied from the offer when the jobber is accepted: later edits never rewrite what was agreed.
    category_name = models.CharField(max_length=80)
    duties = models.JSONField(default=list)
    starts_at = models.DateTimeField()
    duration_minutes = models.PositiveIntegerField()
    pay_xof = models.PositiveIntegerField()
    commune = models.CharField(max_length=60, blank=True)
    quartier = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.ACCEPTED)
    accepted_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "réservation"
        verbose_name_plural = "réservations"
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["offer"],
                condition=Q(
                    status__in=(
                        "accepted",
                        "confirmed",
                        "address_released",
                        "checked_in",
                        "completion_pending",
                        "disputed",
                        "safety_hold",
                    )
                ),
                name="one_live_booking_per_offer",
            )
        ]
        indexes = [
            models.Index(fields=["jobber", "status"]),
            models.Index(fields=["householder", "status"]),
        ]

    def __str__(self):
        return f"{self.category_name} ({self.get_status_display()})"
