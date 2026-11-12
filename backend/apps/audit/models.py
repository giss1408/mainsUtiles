from django.conf import settings
from django.db import models


class AdminAction(models.Model):
    """Append-only record of a staff action."""

    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+")
    action = models.CharField(max_length=80)
    target_type = models.CharField(max_length=80)
    target_id = models.CharField(max_length=64)
    reason = models.TextField(blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "action du personnel"
        verbose_name_plural = "actions du personnel"
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        if self.pk is not None:
            raise ValueError("AdminAction rows cannot be changed")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("AdminAction rows cannot be deleted")

    def __str__(self):
        return f"{self.action} {self.target_type}:{self.target_id}"
