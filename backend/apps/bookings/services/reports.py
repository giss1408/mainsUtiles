"""Problems reported on a booking. A dispute freezes the money until staff decide; a concern only
informs staff and never reaches the other side. Every rule lives here."""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record as audit
from apps.bookings.models import Booking, Payment, Payout, Report
from apps.listings.models import Offer

from .errors import BookingError
from .jobs import _complete
from .payments import _require_staff

RESOLVE = "bookings.resolve_dispute"
TEXT_MIN, TEXT_MAX = 3, 500
DISPUTABLE = (Booking.Status.CHECKED_IN, Booking.Status.COMPLETION_PENDING)
IN_PROGRESS = (Booking.Status.CHECKED_IN, Booking.Status.COMPLETION_PENDING, Booking.Status.DISPUTED)


def _party_booking(user, booking_id) -> Booking:
    if not (user and user.is_active and user.role in ("householder", "jobber")):
        raise BookingError("forbidden")
    try:
        found = Booking.objects.filter(pk=booking_id).first()
    except (ValidationError, ValueError):
        found = None
    if found is None or user.pk not in (found.householder_id, found.jobber_id):
        raise BookingError("forbidden")
    return found


def _concern_allowed(booking: Booking, now) -> bool:
    if booking.status in IN_PROGRESS:
        return True
    return (
        booking.status == Booking.Status.COMPLETED
        and booking.completed_at is not None
        and now <= booking.completed_at + timedelta(days=settings.REVIEW_WINDOW_DAYS)
    )


def report_problem(user, booking_id, *, text: str, dispute: bool) -> Report:
    """A party says something went wrong. A dispute freezes the booking; when one is already open
    the new report is kept as a concern. The other side is never told about a concern."""
    found = _party_booking(user, booking_id)
    words = (text or "").strip()
    if not TEXT_MIN <= len(words) <= TEXT_MAX:
        raise BookingError("report_invalid")
    now = timezone.now()
    with transaction.atomic():
        booking = Booking.objects.select_for_update().get(pk=found.pk)
        kind = Report.Kind.CONCERN
        if dispute:
            already = Report.objects.filter(
                booking=booking, kind=Report.Kind.DISPUTE, status=Report.Status.OPEN
            ).exists()
            if not already:
                if booking.status not in DISPUTABLE:
                    raise BookingError("invalid_state")
                kind = Report.Kind.DISPUTE
        if kind == Report.Kind.CONCERN and not _concern_allowed(booking, now):
            raise BookingError("invalid_state")
        report = Report.objects.create(booking=booking, author=user, kind=kind, text=words)
        if kind == Report.Kind.DISPUTE:
            booking.status = Booking.Status.DISPUTED
            booking.save(update_fields=["status"])
        audit(user, "booking.report", report, booking=str(booking.pk), kind=kind)
    return report


def resolve_dispute(report: Report, *, staff, outcome: str, note: str, jobber_xof: int | None = None) -> None:
    """Staff decide a dispute: pay the jobber, refund the householder, or share the price."""
    _require_staff(staff, RESOLVE)
    reason = (note or "").strip()
    now = timezone.now()
    with transaction.atomic():
        row = Report.objects.select_for_update().get(pk=report.pk)
        booking = Booking.objects.select_for_update().get(pk=row.booking_id)
        if (
            row.kind != Report.Kind.DISPUTE
            or row.status != Report.Status.OPEN
            or booking.status != Booking.Status.DISPUTED
        ):
            raise BookingError("invalid_state")
        if outcome not in Report.Outcome.values:
            raise BookingError("outcome_invalid")
        if not reason:
            raise BookingError("reason_required")
        share = None
        if outcome == Report.Outcome.RELEASE:
            _complete(booking, how="staff", actor=staff)
        elif outcome == Report.Outcome.REFUND:
            booking.status = Booking.Status.CANCELLED
            booking.cancelled_at = now
            booking.cancel_reason = "dispute_refund"
            booking.save(update_fields=["status", "cancelled_at", "cancel_reason"])
            Payment.objects.filter(booking=booking, status=Payment.Status.CONFIRMED).update(
                status=Payment.Status.REFUND_DUE
            )
            Offer.objects.filter(pk=booking.offer_id, status=Offer.Status.BOOKED).update(
                status=Offer.Status.CLOSED, updated_at=now
            )
        else:
            if isinstance(jobber_xof, bool) or not isinstance(jobber_xof, int):
                raise BookingError("split_invalid")
            if not 0 < jobber_xof < booking.pay_xof:
                raise BookingError("split_invalid")
            share = jobber_xof
            booking.status = Booking.Status.COMPLETED
            booking.completed_at = now
            booking.completion = "staff"
            booking.save(update_fields=["status", "completed_at", "completion"])
            Payout.objects.get_or_create(booking=booking, defaults={"amount_xof": share})
            Payment.objects.filter(booking=booking, status=Payment.Status.CONFIRMED).update(
                status=Payment.Status.REFUND_DUE, refund_xof=booking.pay_xof - share
            )
            audit(staff, "booking.complete", booking, how="staff")
        row.status = Report.Status.RESOLVED
        row.outcome = outcome
        row.jobber_xof = share
        row.resolved_by = staff
        row.resolved_at = now
        row.note = reason
        row.save(update_fields=["status", "outcome", "jobber_xof", "resolved_by", "resolved_at", "note"])
        audit(
            staff, "booking.dispute.resolve", row, booking=str(booking.pk), outcome=outcome, jobber_xof=share
        )
    report.refresh_from_db()
