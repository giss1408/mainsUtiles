from .models import AdminAction


def record(actor, action: str, target, reason: str = "", **metadata) -> AdminAction:
    """Write one audit row for a staff action on a model instance."""
    return AdminAction.objects.create(
        actor=actor,
        action=action,
        target_type=target._meta.label_lower,
        target_id=str(target.pk),
        reason=reason,
        metadata=metadata,
    )
