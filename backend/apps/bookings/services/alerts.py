"""What waits for staff, as counts for the staff app. A staff member only sees the counts of the
queues they may work."""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from apps.bookings.models import Booking, Message, Payment, Payout, Report


def counts(user, now=None) -> dict:
    now = now or timezone.now()
    found: dict[str, int] = {}
    if user.has_perm("bookings.verify_payment"):
        waiting = Payment.objects.filter(status=Payment.Status.SUBMITTED)
        limit = now - timedelta(hours=settings.PAYMENT_REVIEW_LATE_HOURS)
        found["payments_waiting"] = waiting.count()
        found["payments_late"] = waiting.filter(submitted_at__lt=limit).count()
    if user.has_perm("bookings.make_refund"):
        found["refunds_waiting"] = Payment.objects.filter(status=Payment.Status.REFUND_DUE).count()
    if user.has_perm("bookings.make_payout"):
        due = Payout.objects.filter(status=Payout.Status.DUE)
        found["payouts_waiting"] = due.count()
        found["payouts_late"] = due.filter(
            due_at__lt=now - timedelta(hours=settings.PAYOUT_LATE_HOURS)
        ).count()
    if user.has_perm("bookings.resolve_dispute"):
        disputes = Report.objects.filter(kind=Report.Kind.DISPUTE, status=Report.Status.OPEN)
        found["disputes_open"] = disputes.count()
        found["disputes_late"] = disputes.filter(
            created_at__lt=now - timedelta(hours=settings.DISPUTE_LATE_HOURS)
        ).count()
        # A jobber who said "arrived" far from the home, while the job is running.
        found["far_checkins"] = Booking.objects.filter(
            status=Booking.Status.CHECKED_IN, checkin_distance_m__gt=settings.CHECKIN_FLAG_METERS
        ).count()
    if user.has_perm("bookings.send_message"):
        pending = Message.objects.filter(status=Message.Status.PENDING)
        urgent_limit = now - timedelta(minutes=settings.MESSAGE_URGENT_LATE_MINUTES)
        normal_limit = now - timedelta(minutes=settings.MESSAGE_LATE_MINUTES)
        found["messages_waiting"] = pending.count()
        found["messages_late"] = (
            pending.filter(urgent=True, created_at__lt=urgent_limit).count()
            + pending.filter(urgent=False, created_at__lt=normal_limit).count()
        )
    return found
