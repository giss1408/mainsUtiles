import uuid

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
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
    # The job itself: when the jobber arrived and left, how it ended, how far the check-in was.
    checked_in_at = models.DateTimeField(null=True, blank=True)
    checked_out_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    # `householder` (confirmed), `timeout` (nobody answered) or `staff` (a dispute was decided).
    completion = models.CharField(max_length=12, blank=True)
    checkin_distance_m = models.PositiveIntegerField(null=True, blank=True)
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
    # What goes back to the householder when it is not the whole price (a split dispute). Null means
    # the whole `pay_xof`; the platform keeps its fee.
    refund_xof = models.PositiveIntegerField(null=True, blank=True)
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


class Payout(models.Model):
    """What staff owe the jobber for a completed booking, and the record that it was sent."""

    class Status(models.TextChoices):
        DUE = "due", "À verser"
        PAID = "paid", "Versé"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    booking = models.OneToOneField(Booking, on_delete=models.PROTECT, related_name="payout")
    amount_xof = models.PositiveIntegerField()
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DUE)
    due_at = models.DateTimeField(auto_now_add=True)
    reference = models.TextField(blank=True)  # encrypted
    paid_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "paiement au jobber"
        verbose_name_plural = "paiements aux jobbers"
        ordering = ["due_at"]
        permissions = [("make_payout", "Peut enregistrer un paiement au jobber")]

    def __str__(self):
        return f"{self.booking_id} / {self.get_status_display()}"


class Report(models.Model):
    """A problem reported on a booking. A dispute freezes the money; a concern only informs staff."""

    class Kind(models.TextChoices):
        DISPUTE = "dispute", "Litige"
        CONCERN = "concern", "Remarque"

    class Status(models.TextChoices):
        OPEN = "open", "Ouvert"
        RESOLVED = "resolved", "Traité"

    class Outcome(models.TextChoices):
        RELEASE = "release", "Payer le jobber"
        REFUND = "refund", "Rembourser le ménage"
        SPLIT = "split", "Partager"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    booking = models.ForeignKey(Booking, on_delete=models.PROTECT, related_name="reports")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    kind = models.CharField(max_length=10, choices=Kind.choices)
    text = models.TextField()
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.OPEN)
    outcome = models.CharField(max_length=10, choices=Outcome.choices, blank=True)
    jobber_xof = models.PositiveIntegerField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "signalement"
        verbose_name_plural = "signalements"
        ordering = ["created_at"]
        permissions = [("resolve_dispute", "Peut trancher un litige")]
        constraints = [
            models.UniqueConstraint(
                fields=["booking"],
                condition=Q(kind="dispute", status="open"),
                name="one_open_dispute_per_booking",
            )
        ]
        indexes = [models.Index(fields=["kind", "status", "created_at"])]

    def __str__(self):
        return f"{self.get_kind_display()} {self.booking_id}"


class Review(models.Model):
    """What one side thinks of the other after a completed booking. Hidden until both are in."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    booking = models.ForeignKey(Booking, on_delete=models.PROTECT, related_name="reviews")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    about = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    stars = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "avis"
        verbose_name_plural = "avis"
        ordering = ["created_at"]
        constraints = [
            models.UniqueConstraint(fields=["booking", "author"], name="one_review_per_author_and_booking")
        ]
        indexes = [models.Index(fields=["about", "published_at"])]

    def __str__(self):
        return f"{self.stars}/5 ({self.booking_id})"
