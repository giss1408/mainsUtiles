enum StepStatus {
  notStarted,
  submitted,
  inReview,
  confirmed,
  refused,
  expired;

  /// Reads the server value. A value this version does not know is shown as
  /// "sent", which never invites the user to submit again by mistake.
  static StepStatus parse(String? value) => switch (value) {
        'not_started' => StepStatus.notStarted,
        'in_review' => StepStatus.inReview,
        'confirmed' => StepStatus.confirmed,
        'refused' => StepStatus.refused,
        'expired' => StepStatus.expired,
        _ => StepStatus.submitted,
      };

  /// The user may (re)start the step.
  bool get canStart =>
      this == StepStatus.notStarted || this == StepStatus.refused || this == StepStatus.expired;
}

class VerificationStep {
  const VerificationStep({required this.status, this.reason = ''});

  factory VerificationStep.fromJson(Map<String, dynamic> json) => VerificationStep(
        status: StepStatus.parse(json['status'] as String?),
        reason: (json['reason'] as String?) ?? '',
      );

  final StepStatus status;

  /// Why staff refused; empty otherwise.
  final String reason;
}

class AddressState extends VerificationStep {
  const AddressState({
    required super.status,
    super.reason,
    this.commune = '',
    this.quartier = '',
    this.expiresAt,
  });

  factory AddressState.fromJson(Map<String, dynamic> json) {
    final expires = json['expires_at'] as String?;
    return AddressState(
      status: StepStatus.parse(json['status'] as String?),
      reason: (json['reason'] as String?) ?? '',
      commune: (json['commune'] as String?) ?? '',
      quartier: (json['quartier'] as String?) ?? '',
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  }

  final String commune;
  final String quartier;
  final DateTime? expiresAt;
}

/// The householder's verification progress, as the server reports it.
class VerificationChecklist {
  const VerificationChecklist({
    required this.tier,
    required this.reviewHours,
    required this.communes,
    required this.identity,
    required this.address,
    required this.homeLocation,
    this.guarantor = const VerificationStep(status: StepStatus.notStarted),
  });

  factory VerificationChecklist.fromJson(Map<String, dynamic> json) => VerificationChecklist(
        tier: (json['tier'] as String?) ?? 'H0',
        reviewHours: (json['review_hours'] as num?)?.toInt() ?? 24,
        communes: ((json['communes'] as List?) ?? const []).map((c) => '$c').toList(),
        identity: VerificationStep.fromJson(Map<String, dynamic>.from(json['identity'] as Map)),
        address: _optional(json['address'], AddressState.fromJson, const _NotStartedAddress()),
        homeLocation: _optional(
          json['home_location'],
          VerificationStep.fromJson,
          const VerificationStep(status: StepStatus.notStarted),
        ),
        guarantor: _optional(
          json['guarantor'],
          VerificationStep.fromJson,
          const VerificationStep(status: StepStatus.notStarted),
        ),
      );

  /// A step the server does not report for this role counts as not started.
  static T _optional<T>(Object? json, T Function(Map<String, dynamic>) parse, T fallback) =>
      json is Map ? parse(Map<String, dynamic>.from(json)) : fallback;

  final String tier;
  final int reviewHours;
  final List<String> communes;
  final VerificationStep identity;
  final AddressState address;
  final VerificationStep homeLocation;

  /// Reported for jobbers only.
  final VerificationStep guarantor;

  /// A jobber's tiers start with J, a householder's with H.
  bool get forJobber => tier.startsWith('J');

  bool get verified => tier == 'H1' || tier == 'J1';
}

class _NotStartedAddress extends AddressState {
  const _NotStartedAddress() : super(status: StepStatus.notStarted);
}
