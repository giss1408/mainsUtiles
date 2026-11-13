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
        PAYMENT_REVIEW = "payment_review", "Paiement à vérifier"
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
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.TextField(blank=True)

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
                        "payment_review",
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


class PaymentMethodQuerySet(models.QuerySet):
    def available(self):
        """Active methods that have a receiving number: the only ones a householder is shown."""
        return self.filter(active=True).exclude(number="")


class PaymentMethod(models.Model):
    """A mobile-money account of the platform that householders pay into. Edited by staff."""

    class Provider(models.TextChoices):
        WAVE = "wave", "Wave"
        MTN_MOMO = "mtn_momo", "MTN MoMo"
        ORANGE_MONEY = "orange_money", "Orange Money"

    provider = models.CharField(max_length=20, choices=Provider.choices)
    number = models.CharField(max_length=30, blank=True)
    account_name = models.CharField(max_length=80, blank=True)
    active = models.BooleanField(default=False)
    position = models.PositiveSmallIntegerField(default=0)

    objects = PaymentMethodQuerySet.as_manager()

    class Meta:
        verbose_name = "moyen de paiement"
        verbose_name_plural = "moyens de paiement"
        ordering = ["position", "provider"]

    def __str__(self):
        return self.get_provider_display()


class Payment(models.Model):
    """What a householder sent to pay for a booking, and what staff decided about it."""

    class Status(models.TextChoices):
        SUBMITTED = "submitted", "À vérifier"
        CONFIRMED = "confirmed", "Confirmé"
        REFUSED = "refused", "Refusé"
        REFUND_DUE = "refund_due", "Remboursement à faire"
        REFUNDED = "refunded", "Remboursé"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    booking = models.ForeignKey(Booking, on_delete=models.PROTECT, related_name="payments")
    method = models.ForeignKey(PaymentMethod, on_delete=models.PROTECT, related_name="+")
    amount_xof = models.PositiveIntegerField()
    fee_xof = models.PositiveIntegerField(default=0)
    # What the householder typed from their mobile-money receipt. Encrypted; the hash finds repeats.
    reference = models.TextField()
    reference_hash = models.CharField(max_length=64, db_index=True)
    proof = models.ForeignKey("verification.VerificationPhoto", on_delete=models.PROTECT, related_name="+")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.SUBMITTED)
    reason = models.TextField(blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    refund_reference = models.TextField(blank=True)  # encrypted
    refunded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    refunded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "paiement"
        verbose_name_plural = "paiements"
        ordering = ["submitted_at"]
        permissions = [
            ("verify_payment", "Peut confirmer ou refuser un paiement"),
            ("make_refund", "Peut enregistrer un remboursement"),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["booking"],
                condition=Q(status__in=("submitted", "confirmed", "refund_due")),
                name="one_open_payment_per_booking",
            ),
            models.UniqueConstraint(
                fields=["reference_hash"],
                condition=Q(status__in=("confirmed", "refund_due", "refunded")),
                name="one_confirmed_reference",
            ),
        ]
        indexes = [models.Index(fields=["status", "submitted_at"])]

    def __str__(self):
        return f"{self.booking_id} / {self.get_status_display()}"
