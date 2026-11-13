enum ApplicationStatus {
  pending,
  accepted,
  declined,
  withdrawn;

  /// An unknown value reads as pending: it never claims the jobber was chosen.
  static ApplicationStatus parse(String? value) => switch (value) {
        'accepted' => ApplicationStatus.accepted,
        'declined' => ApplicationStatus.declined,
        'withdrawn' => ApplicationStatus.withdrawn,
        _ => ApplicationStatus.pending,
      };
}

/// What a jobber sees of the householder before applying. No name, no contact.
class HouseholderTrust {
  const HouseholderTrust({required this.tier, required this.jobsDone, this.rating});

  factory HouseholderTrust.fromJson(Map<String, dynamic> json) => HouseholderTrust(
        tier: (json['tier'] as String?) ?? 'H0',
        jobsDone: (json['jobs_done'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toDouble(),
      );

  final String tier;
  final int jobsDone;

  /// Null until reviews exist.
  final double? rating;
}

/// The caller's own live application on an offer.
class MyApplicationRef {
  const MyApplicationRef({required this.id, required this.status});

  factory MyApplicationRef.fromJson(Map<String, dynamic> json) => MyApplicationRef(
        id: json['id'] as String,
        status: ApplicationStatus.parse(json['status'] as String?),
      );

  final String id;
  final ApplicationStatus status;
}

/// The jobber chosen for an offer, as the householder sees them: a first name only.
class BookingSummary {
  const BookingSummary({required this.id, required this.status, required this.jobberFirstName});

  factory BookingSummary.fromJson(Map<String, dynamic> json) => BookingSummary(
        id: json['id'] as String,
        status: (json['status'] as String?) ?? 'accepted',
        jobberFirstName: (json['jobber_first_name'] as String?) ?? '',
      );

  final String id;
  final String status;
  final String jobberFirstName;
}

class BookingRef {
  const BookingRef({required this.id, required this.status});

  factory BookingRef.fromJson(Map<String, dynamic> json) =>
      BookingRef(id: json['id'] as String, status: (json['status'] as String?) ?? 'accepted');

  final String id;
  final String status;
}

/// The offer behind an application, as the jobber's list shows it.
class ApplicationOffer {
  const ApplicationOffer({
    required this.id,
    required this.categoryName,
    required this.startsAt,
    required this.durationMinutes,
    required this.payXof,
    required this.commune,
    required this.quartier,
    required this.status,
  });

  factory ApplicationOffer.fromJson(Map<String, dynamic> json) => ApplicationOffer(
        id: json['id'] as String,
        categoryName: (json['category_name'] as String?) ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        payXof: (json['pay_xof'] as num).toInt(),
        commune: (json['commune'] as String?) ?? '',
        quartier: (json['quartier'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
      );

  final String id;
  final String categoryName;
  final DateTime startsAt;
  final int durationMinutes;
  final int payXof;
  final String commune;
  final String quartier;
  final String status;
}

class JobberApplication {
  const JobberApplication({
    required this.id,
    required this.status,
    required this.message,
    required this.createdAt,
    required this.offer,
    this.booking,
  });

  factory JobberApplication.fromJson(Map<String, dynamic> json) => JobberApplication(
        id: json['id'] as String,
        status: ApplicationStatus.parse(json['status'] as String?),
        message: (json['message'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        offer: ApplicationOffer.fromJson(Map<String, dynamic>.from(json['offer'] as Map)),
        booking: json['booking'] == null
            ? null
            : BookingRef.fromJson(Map<String, dynamic>.from(json['booking'] as Map)),
      );

  final String id;
  final ApplicationStatus status;
  final String message;
  final DateTime createdAt;
  final ApplicationOffer offer;
  final BookingRef? booking;

  JobberApplication withStatus(ApplicationStatus value) => JobberApplication(
        id: id,
        status: value,
        message: message,
        createdAt: createdAt,
        offer: offer,
        booking: booking,
      );
}

/// What a householder sees of an applicant. A first name, never a contact.
class ApplicantCard {
  const ApplicantCard({
    required this.id,
    required this.firstName,
    required this.tier,
    required this.jobsDone,
    required this.message,
    required this.createdAt,
    this.rating,
  });

  factory ApplicantCard.fromJson(Map<String, dynamic> json) => ApplicantCard(
        id: json['id'] as String,
        firstName: (json['first_name'] as String?) ?? '',
        tier: (json['tier'] as String?) ?? 'J1',
        jobsDone: (json['jobs_done'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toDouble(),
        message: (json['message'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;
  final String firstName;
  final String tier;
  final int jobsDone;
  final double? rating;
  final String message;
  final DateTime createdAt;
}

/// A booking as its jobber sees it. No address and no householder.
class JobberBooking {
  const JobberBooking({
    required this.id,
    required this.status,
    required this.categoryName,
    required this.startsAt,
    required this.durationMinutes,
    required this.payXof,
    required this.commune,
    required this.quartier,
    required this.addressAvailableFrom,
    required this.payment,
  });

  factory JobberBooking.fromJson(Map<String, dynamic> json) => JobberBooking(
        id: json['id'] as String,
        status: (json['status'] as String?) ?? 'accepted',
        categoryName: (json['category_name'] as String?) ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        payXof: (json['pay_xof'] as num).toInt(),
        commune: (json['commune'] as String?) ?? '',
        quartier: (json['quartier'] as String?) ?? '',
        addressAvailableFrom: DateTime.parse(json['address_available_from'] as String).toLocal(),
        payment: (json['payment'] as String?) ?? 'pending',
      );

  final String id;
  final String status;
  final String categoryName;
  final DateTime startsAt;
  final int durationMinutes;
  final int payXof;
  final String commune;
  final String quartier;

  /// When the exact pin is shown.
  final DateTime addressAvailableFrom;

  /// `pending` (not paid yet), `review` (staff are checking) or `confirmed`.
  final String payment;
}

/// One way to pay, as staff set it up: the platform's number to send the money to.
class PaymentMethodInfo {
  const PaymentMethodInfo({
    required this.id,
    required this.provider,
    required this.providerLabel,
    required this.number,
    required this.accountName,
  });

  factory PaymentMethodInfo.fromJson(Map<String, dynamic> json) => PaymentMethodInfo(
        id: (json['id'] as num).toInt(),
        provider: (json['provider'] as String?) ?? '',
        providerLabel: (json['provider_label'] as String?) ?? '',
        number: (json['number'] as String?) ?? '',
        accountName: (json['account_name'] as String?) ?? '',
      );

  final int id;
  final String provider;
  final String providerLabel;
  final String number;
  final String accountName;
}

/// What became of the householder's proof of payment.
class PaymentState {
  const PaymentState({required this.status, required this.reason});

  factory PaymentState.fromJson(Map<String, dynamic> json) => PaymentState(
        status: (json['status'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
      );

  final String status;
  final String reason;

  bool get refused => status == 'refused';
}

/// A booking as its householder sees it: what to pay, where, until when, and who is coming.
class BookingDetail {
  const BookingDetail({
    required this.id,
    required this.status,
    required this.amountXof,
    required this.feeXof,
    required this.payDeadline,
    required this.methods,
    required this.cancellable,
    required this.jobberFirstName,
    this.jobberFullName,
    this.hasPhoto = false,
    this.payment,
  });

  factory BookingDetail.fromJson(Map<String, dynamic> json) {
    final jobber = Map<String, dynamic>.from((json['jobber'] as Map?) ?? const {});
    return BookingDetail(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'accepted',
      amountXof: (json['amount_xof'] as num).toInt(),
      feeXof: (json['fee_xof'] as num?)?.toInt() ?? 0,
      payDeadline: DateTime.parse(json['pay_deadline'] as String).toLocal(),
      methods: ((json['methods'] as List?) ?? const [])
          .map((m) => PaymentMethodInfo.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      payment: json['payment'] == null
          ? null
          : PaymentState.fromJson(Map<String, dynamic>.from(json['payment'] as Map)),
      jobberFirstName: (jobber['first_name'] as String?) ??
          ((jobber['full_name'] as String?) ?? '').split(' ').first,
      jobberFullName: jobber['full_name'] as String?,
      hasPhoto: jobber['has_photo'] == true,
      cancellable: json['cancellable'] == true,
    );
  }

  final String id;
  final String status;
  final int amountXof;
  final int feeXof;
  final DateTime payDeadline;
  final List<PaymentMethodInfo> methods;
  final PaymentState? payment;
  final String jobberFirstName;

  /// Known only once the payment is confirmed.
  final String? jobberFullName;
  final bool hasPhoto;
  final bool cancellable;
}

/// The exact pin of the home, shown to the booked jobber in the release window only.
class ReleasedAddress {
  const ReleasedAddress({
    required this.latitude,
    required this.longitude,
    required this.commune,
    required this.quartier,
  });

  factory ReleasedAddress.fromJson(Map<String, dynamic> json) => ReleasedAddress(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        commune: (json['commune'] as String?) ?? '',
        quartier: (json['quartier'] as String?) ?? '',
      );

  final double latitude;
  final double longitude;
  final String commune;
  final String quartier;
}

/// The reply to applying: enough to show "candidature envoyée".
class ApplicationReceipt {
  const ApplicationReceipt({required this.id, required this.status});

  factory ApplicationReceipt.fromJson(Map<String, dynamic> json) => ApplicationReceipt(
        id: json['id'] as String,
        status: ApplicationStatus.parse(json['status'] as String?),
      );

  final String id;
  final ApplicationStatus status;
}
