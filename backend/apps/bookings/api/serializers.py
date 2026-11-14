from rest_framework import serializers


class ApplyBodySerializer(serializers.Serializer):
    # The length limit (APPLICATION_MESSAGE_MAX) is enforced by the service, which answers with a
    # French message; the schema does not repeat it.
    message = serializers.CharField(required=False, allow_blank=True, default="")


class OfferLineSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    pay_xof = serializers.IntegerField()
    commune = serializers.CharField()
    quartier = serializers.CharField()
    status = serializers.CharField()


class BookingRefSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()


class ApplicationSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    offer_id = serializers.UUIDField()
    status = serializers.CharField()
    created_at = serializers.DateTimeField()


class ApplicationItemSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    message = serializers.CharField()
    created_at = serializers.DateTimeField()
    offer = OfferLineSerializer()
    booking = BookingRefSerializer(allow_null=True)


class JobberBookingSerializer(serializers.Serializer):
    """A booking as its jobber sees it. Never an address and never the householder."""

    id = serializers.UUIDField()
    status = serializers.CharField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    duration_minutes = serializers.IntegerField()
    pay_xof = serializers.IntegerField()
    commune = serializers.CharField()
    quartier = serializers.CharField()
    address_available_from = serializers.DateTimeField()
    payment = serializers.CharField()
    checkin_from = serializers.DateTimeField()
    checked_in_at = serializers.DateTimeField(allow_null=True)
    checked_out_at = serializers.DateTimeField(allow_null=True)
    auto_confirm_at = serializers.DateTimeField(allow_null=True)
    payout = serializers.ChoiceField(choices=["none", "due", "paid"])
    reviewable = serializers.BooleanField()


class ApplicantSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    first_name = serializers.CharField()
    tier = serializers.CharField()
    jobs_done = serializers.IntegerField()
    rating = serializers.FloatField(allow_null=True)
    message = serializers.CharField()
    created_at = serializers.DateTimeField()


class AcceptedBookingSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    jobber_first_name = serializers.CharField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    pay_xof = serializers.IntegerField()


class MethodSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    provider = serializers.CharField()
    provider_label = serializers.CharField()
    number = serializers.CharField()
    account_name = serializers.CharField()


class PaymentStateSerializer(serializers.Serializer):
    status = serializers.CharField()
    reason = serializers.CharField(allow_blank=True)


class HouseholderBookingSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()
    amount_xof = serializers.IntegerField()
    fee_xof = serializers.IntegerField()
    pay_deadline = serializers.DateTimeField()
    methods = MethodSerializer(many=True)
    payment = PaymentStateSerializer(allow_null=True)
    jobber = serializers.DictField(child=serializers.JSONField())
    cancellable = serializers.BooleanField()
    checked_in_at = serializers.DateTimeField(allow_null=True)
    checked_out_at = serializers.DateTimeField(allow_null=True)
    auto_confirm_at = serializers.DateTimeField(allow_null=True)
    reviewable = serializers.BooleanField()
    jobber_rating = serializers.FloatField(allow_null=True)


class PaymentBodySerializer(serializers.Serializer):
    method_id = serializers.IntegerField()
    reference = serializers.CharField(allow_blank=True, trim_whitespace=False)
    screenshot = serializers.FileField()
    captured_at = serializers.DateTimeField()


class PaymentReceiptSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()


class CancelBodySerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default="", max_length=500)


class CancelledSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()


class AddressSerializer(serializers.Serializer):
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()
    commune = serializers.CharField()
    quartier = serializers.CharField()


class PaymentItemSerializer(serializers.Serializer):
    """A payment in a staff queue. Never a reference, a name or a phone."""

    id = serializers.UUIDField()
    category_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    amount_xof = serializers.IntegerField()
    method_label = serializers.CharField()
    submitted_at = serializers.DateTimeField()
    late = serializers.BooleanField()
    action = serializers.CharField()


class PaymentDetailSerializer(PaymentItemSerializer):
    fee_xof = serializers.IntegerField()
    reference = serializers.CharField()
    method_number = serializers.CharField()
    seen_before = serializers.BooleanField()
    status = serializers.CharField()


class ConfirmBodySerializer(serializers.Serializer):
    amount_matches = serializers.BooleanField(default=False)
    reference_matches = serializers.BooleanField(default=False)


class RefuseBodySerializer(serializers.Serializer):
    reason = serializers.CharField(allow_blank=True, default="", max_length=300)


class RefundBodySerializer(serializers.Serializer):
    reference = serializers.CharField(allow_blank=True, default="", max_length=40)


class CheckInBodySerializer(serializers.Serializer):
    lat = serializers.FloatField(required=False, allow_null=True, default=None)
    lng = serializers.FloatField(required=False, allow_null=True, default=None)
    accuracy_m = serializers.FloatField(required=False, allow_null=True, default=None)


class JobStateSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    status = serializers.CharField()


class ReportBodySerializer(serializers.Serializer):
    text = serializers.CharField(allow_blank=True, trim_whitespace=False, max_length=2000)
    dispute = serializers.BooleanField(default=False)


class ReportReceiptSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    kind = serializers.CharField()
    booking_status = serializers.CharField()


class ReviewBodySerializer(serializers.Serializer):
    stars = serializers.IntegerField()
    comment = serializers.CharField(required=False, allow_blank=True, default="", max_length=2000)


class ReviewItemSerializer(serializers.Serializer):
    stars = serializers.IntegerField()
    comment = serializers.CharField(allow_blank=True)


class ReviewStateSerializer(serializers.Serializer):
    mine = ReviewItemSerializer(allow_null=True)
    theirs = ReviewItemSerializer(allow_null=True)


class WhatsAppLinkSerializer(serializers.Serializer):
    whatsapp_url = serializers.CharField()


class MessageItemSerializer(serializers.Serializer):
    """A message waiting for staff. Never its text, a name or a number."""

    id = serializers.UUIDField()
    kind = serializers.CharField()
    kind_label = serializers.CharField()
    recipient_role = serializers.CharField()
    urgent = serializers.BooleanField()
    late = serializers.BooleanField()
    created_at = serializers.DateTimeField()


class MessageDetailSerializer(MessageItemSerializer):
    text = serializers.CharField()
    category_name = serializers.CharField()


class PayoutItemSerializer(serializers.Serializer):
    """A payout in the staff queue. Never the jobber's phone or a reference."""

    id = serializers.UUIDField()
    category_name = serializers.CharField()
    amount_xof = serializers.IntegerField()
    due_at = serializers.DateTimeField()
    late = serializers.BooleanField()


class PayoutDetailSerializer(PayoutItemSerializer):
    jobber_phone = serializers.CharField()
    completed_at = serializers.DateTimeField(allow_null=True)
    payable = serializers.BooleanField()


class PayBodySerializer(serializers.Serializer):
    reference = serializers.CharField(allow_blank=True, trim_whitespace=False, max_length=200)


class DisputeItemSerializer(serializers.Serializer):
    """An open dispute in the staff queue. Never what was written."""

    id = serializers.UUIDField()
    category_name = serializers.CharField()
    created_at = serializers.DateTimeField()
    late = serializers.BooleanField()


class DisputeDetailSerializer(DisputeItemSerializer):
    text = serializers.CharField()
    author_side = serializers.CharField()
    jobber_name = serializers.CharField()
    householder_name = serializers.CharField()
    starts_at = serializers.DateTimeField()
    pay_xof = serializers.IntegerField()
    checked_in_at = serializers.DateTimeField(allow_null=True)
    checked_out_at = serializers.DateTimeField(allow_null=True)
    distance_m = serializers.IntegerField(allow_null=True)
    far = serializers.BooleanField()
    payment_state = serializers.CharField()


class ResolveBodySerializer(serializers.Serializer):
    outcome = serializers.CharField(allow_blank=True)
    note = serializers.CharField(allow_blank=True, trim_whitespace=False, max_length=500)
    jobber_xof = serializers.IntegerField(required=False, allow_null=True, default=None)


class AlertsSerializer(serializers.Serializer):
    """Counts of what waits. A key is absent when the caller may not work that queue."""

    payments_waiting = serializers.IntegerField(required=False)
    payments_late = serializers.IntegerField(required=False)
    refunds_waiting = serializers.IntegerField(required=False)
    payouts_waiting = serializers.IntegerField(required=False)
    payouts_late = serializers.IntegerField(required=False)
    disputes_open = serializers.IntegerField(required=False)
    disputes_late = serializers.IntegerField(required=False)
    far_checkins = serializers.IntegerField(required=False)
    messages_waiting = serializers.IntegerField(required=False)
    messages_late = serializers.IntegerField(required=False)
