import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


class Status(models.TextChoices):
    SUBMITTED = "submitted", "Envoyé"
    IN_REVIEW = "in_review", "En cours de vérification"
    CONFIRMED = "confirmed", "Confirmé"
    REFUSED = "refused", "Refusé"
    EXPIRED = "expired", "Expiré"


# A user has at most one record of each kind in these states.
OPEN = (Status.SUBMITTED, Status.IN_REVIEW, Status.CONFIRMED)
# Staff may still decide a record in these states.
UNDECIDED = (Status.SUBMITTED, Status.IN_REVIEW)


def _one_open_per_user(name: str) -> models.UniqueConstraint:
    return models.UniqueConstraint(fields=["user"], condition=Q(status__in=OPEN), name=name)


class VerificationPhoto(models.Model):
    """A photo taken in the app. The file on disk is encrypted; only its name is stored here."""

    class Kind(models.TextChoices):
        ID_FRONT = "id_front", "Recto du document"
        ID_BACK = "id_back", "Verso du document"
        SELFIE = "selfie", "Visage"
        ADDRESS_PROOF = "address_proof", "Justificatif de domicile"
        GUARANTOR_BILL = "guarantor_bill", "Facture du garant"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    kind = models.CharField(max_length=20, choices=Kind.choices)
    storage_name = models.CharField(max_length=80, unique=True)
    # Fingerprint of the original image, to notice the same image sent by two accounts.
    sha256 = models.CharField(max_length=64, db_index=True)
    captured_at = models.DateTimeField()
    capture_position = models.TextField(blank=True)  # encrypted "lat,lng"
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.get_kind_display()} ({self.pk})"


class Reviewed(models.Model):
    """What every reviewed record has in common."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.SUBMITTED)
    flags = models.JSONField(default=list, blank=True)
    reason = models.TextField(blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        abstract = True
        ordering = ["created_at"]


class IdentityVerification(Reviewed):
    """Photos of an identity document and a selfie, and what staff read on them."""

    front = models.ForeignKey(VerificationPhoto, on_delete=models.PROTECT, related_name="+")
    back = models.ForeignKey(VerificationPhoto, on_delete=models.PROTECT, related_name="+")
    selfie = models.ForeignKey(VerificationPhoto, on_delete=models.PROTECT, related_name="+")
    document_type = models.CharField(max_length=30)
    # Recorded by staff, stored encrypted.
    full_name = models.TextField(blank=True)
    date_of_birth = models.TextField(blank=True)
    document_number = models.TextField(blank=True)
    document_number_hash = models.CharField(max_length=64, blank=True)
    document_expires_on = models.DateField(null=True, blank=True)

    class Meta(Reviewed.Meta):
        verbose_name = "vérification d'identité"
        verbose_name_plural = "vérifications d'identité"
        indexes = [models.Index(fields=["status", "created_at"])]
        constraints = [
            _one_open_per_user("one_open_identity_per_user"),
            models.UniqueConstraint(
                fields=["document_number_hash"],
                condition=Q(status="confirmed"),
                name="one_account_per_identity_document",
            ),
        ]
        permissions = [
            ("review_verification", "Peut confirmer ou refuser une vérification"),
            ("view_verification_photo", "Peut voir les photos de vérification"),
        ]

    def __str__(self):
        return f"Identité de {self.user} ({self.get_status_display()})"


class AddressProof(Reviewed):
    """A bill or certificate tying the householder to a home."""

    photo = models.ForeignKey(VerificationPhoto, on_delete=models.PROTECT, related_name="+")
    document_type = models.CharField(max_length=30)
    # Shown to jobbers on offers later, so not encrypted.
    commune = models.CharField(max_length=60)
    quartier = models.CharField(max_length=80)
    # Recorded by staff, stored encrypted.
    holder_name = models.TextField(blank=True)
    reference_number = models.TextField(blank=True)
    reference_hash = models.CharField(max_length=64, blank=True)
    issued_on = models.DateField(null=True, blank=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    class Meta(Reviewed.Meta):
        verbose_name = "justificatif de domicile"
        verbose_name_plural = "justificatifs de domicile"
        indexes = [models.Index(fields=["status", "created_at"])]
        constraints = [
            _one_open_per_user("one_open_address_proof_per_user"),
            models.UniqueConstraint(
                fields=["reference_hash"],
                condition=Q(status="confirmed"),
                name="one_householder_per_address_document",
            ),
        ]

    def __str__(self):
        return f"Justificatif de {self.user} ({self.get_status_display()})"


class HomeLocation(Reviewed):
    """The position recorded by the app at the householder's home. Judged with the address proof."""

    latitude = models.TextField()  # encrypted
    longitude = models.TextField()  # encrypted
    accuracy_m = models.PositiveIntegerField()
    mock_location = models.BooleanField(default=False)
    captured_at = models.DateTimeField()

    class Meta(Reviewed.Meta):
        verbose_name = "position du domicile"
        verbose_name_plural = "positions du domicile"
        constraints = [_one_open_per_user("one_open_home_location_per_user")]

    def __str__(self):
        return f"Position de {self.user} ({self.get_status_display()})"


class Guarantor(Reviewed):
    """Someone who vouches for a jobber, and the bill that ties them to a fixed address."""

    class Relationship(models.TextChoices):
        PARENT = "parent", "Parent"
        RELATIVE = "relative", "Famille"
        LANDLORD = "landlord", "Propriétaire"
        OTHER = "other", "Autre"

    photo = models.ForeignKey(VerificationPhoto, on_delete=models.PROTECT, related_name="+")
    document_type = models.CharField(max_length=30)
    # Typed by the jobber, stored encrypted: they belong to a person who is not a user.
    guarantor_name = models.TextField()
    guarantor_phone = models.TextField()
    guarantor_phone_hash = models.CharField(max_length=64, db_index=True)
    relationship = models.CharField(max_length=20, choices=Relationship.choices)
    # Recorded by staff from the bill, stored encrypted.
    holder_name = models.TextField(blank=True)
    reference_number = models.TextField(blank=True)
    reference_hash = models.CharField(max_length=64, blank=True, db_index=True)
    issued_on = models.DateField(null=True, blank=True)
    contacted_at = models.DateTimeField(null=True, blank=True)
    contacted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    confirmed_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    class Meta(Reviewed.Meta):
        verbose_name = "garant"
        verbose_name_plural = "garants"
        indexes = [models.Index(fields=["status", "created_at"])]
        constraints = [_one_open_per_user("one_open_guarantor_per_user")]

    def __str__(self):
        return f"Garant de {self.user} ({self.get_status_display()})"
