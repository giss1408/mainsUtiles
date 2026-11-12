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

class StepState {
  const StepState({required this.status, this.reason = ''});

  factory StepState.fromJson(Map<String, dynamic> json) => StepState(
        status: StepStatus.parse(json['status'] as String?),
        reason: (json['reason'] as String?) ?? '',
      );

  final StepStatus status;

  /// Why staff refused; empty otherwise.
  final String reason;
}

class AddressState extends StepState {
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
  });

  factory VerificationChecklist.fromJson(Map<String, dynamic> json) => VerificationChecklist(
        tier: (json['tier'] as String?) ?? 'H0',
        reviewHours: (json['review_hours'] as num?)?.toInt() ?? 24,
        communes: ((json['communes'] as List?) ?? const []).map((c) => '$c').toList(),
        identity: StepState.fromJson(Map<String, dynamic>.from(json['identity'] as Map)),
        address: AddressState.fromJson(Map<String, dynamic>.from(json['address'] as Map)),
        homeLocation: StepState.fromJson(Map<String, dynamic>.from(json['home_location'] as Map)),
      );

  final String tier;
  final int reviewHours;
  final List<String> communes;
  final StepState identity;
  final AddressState address;
  final StepState homeLocation;

  bool get verified => tier == 'H1';
}
