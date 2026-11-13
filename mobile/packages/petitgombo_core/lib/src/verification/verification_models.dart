enum StepStatus {
  notStarted,
  submitted,
  inReview,
  confirmed,
  refused,
  expired,
  inProgress;

  /// Reads the server value. A value this version does not know is shown as
  /// "sent", which never invites the user to submit again by mistake.
  static StepStatus parse(String? value) => switch (value) {
        'not_started' => StepStatus.notStarted,
        'in_review' => StepStatus.inReview,
        'confirmed' => StepStatus.confirmed,
        'refused' => StepStatus.refused,
        'expired' => StepStatus.expired,
        'in_progress' => StepStatus.inProgress,
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

/// The trusted contact step: no review, only counts.
class ContactStep extends VerificationStep {
  const ContactStep({required super.status, this.confirmed = 0, this.pending = 0});

  factory ContactStep.fromJson(Map<String, dynamic> json) => ContactStep(
        status: StepStatus.parse(json['status'] as String?),
        confirmed: (json['confirmed'] as num?)?.toInt() ?? 0,
        pending: (json['pending'] as num?)?.toInt() ?? 0,
      );

  final int confirmed;
  final int pending;
}

/// The safety briefing step: how many cards were answered, and how many are new.
class BriefingStep extends VerificationStep {
  const BriefingStep({
    required super.status,
    this.answered = 0,
    this.total = 0,
    this.newCards = 0,
  });

  factory BriefingStep.fromJson(Map<String, dynamic> json) => BriefingStep(
        status: StepStatus.parse(json['status'] as String?),
        answered: (json['answered'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        newCards: (json['new_cards'] as num?)?.toInt() ?? 0,
      );

  final int answered;
  final int total;

  /// Active cards not answered yet; after J1 these are cards added later.
  final int newCards;
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
    this.required = const ['identity', 'guarantor'],
    this.trustedContact = const ContactStep(status: StepStatus.notStarted),
    this.briefing = const BriefingStep(status: StepStatus.notStarted),
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
        required: json['required'] is List
            ? (json['required'] as List).map((step) => '$step').toList()
            : const ['identity', 'guarantor'],
        trustedContact: _optional(
          json['trusted_contact'],
          ContactStep.fromJson,
          const ContactStep(status: StepStatus.notStarted),
        ),
        briefing: _optional(
          json['briefing'],
          BriefingStep.fromJson,
          const BriefingStep(status: StepStatus.notStarted),
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

  /// The steps a jobber needs for J1, as the server lists them.
  final List<String> required;

  /// Reported for jobbers only.
  final ContactStep trustedContact;
  final BriefingStep briefing;

  /// A jobber's tiers start with J, a householder's with H.
  bool get forJobber => tier.startsWith('J');

  bool get verified => tier == 'H1' || tier == 'J1';
}

class _NotStartedAddress extends AddressState {
  const _NotStartedAddress() : super(status: StepStatus.notStarted);
}

enum ContactState {
  pending,
  confirmed,
  replaced;

  static ContactState parse(String? value) => switch (value) {
        'confirmed' => ContactState.confirmed,
        'replaced' => ContactState.replaced,
        _ => ContactState.pending,
      };
}

/// A trusted contact as the jobber sees it: a name and a state, never the number.
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.status,
    this.replaces,
    this.awaitingCode = false,
    this.endsAt,
  });

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    final ends = json['ends_at'] as String?;
    return TrustedContact(
      id: '${json['id']}',
      name: (json['name'] as String?) ?? '',
      relationship: (json['relationship'] as String?) ?? 'other',
      status: ContactState.parse(json['status'] as String?),
      replaces: json['replaces'] as String?,
      awaitingCode: json['awaiting_code'] == true,
      endsAt: ends == null ? null : DateTime.tryParse(ends),
    );
  }

  final String id;
  final String name;
  final String relationship;
  final ContactState status;

  /// The contact this one takes over from, when it is a replacement.
  final String? replaces;

  /// The jobber asked for a code and staff have not sent it yet.
  final bool awaitingCode;

  /// When a confirmed contact stops counting, once its replacement is noticed.
  final DateTime? endsAt;
}

class BriefingCard {
  const BriefingCard({
    required this.id,
    required this.title,
    required this.body,
    required this.question,
    required this.choices,
    required this.answered,
  });

  factory BriefingCard.fromJson(Map<String, dynamic> json) => BriefingCard(
        id: '${json['id']}',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        question: (json['question'] as String?) ?? '',
        choices: ((json['choices'] as List?) ?? const []).map((c) => '$c').toList(),
        answered: json['answered'] == true,
      );

  final String id;
  final String title;
  final String body;
  final String question;
  final List<String> choices;
  final bool answered;

  BriefingCard markAnswered() => BriefingCard(
        id: id,
        title: title,
        body: body,
        question: question,
        choices: choices,
        answered: true,
      );
}

class BriefingAnswer {
  const BriefingAnswer({required this.correct, required this.explanation, required this.complete});

  factory BriefingAnswer.fromJson(Map<String, dynamic> json) => BriefingAnswer(
        correct: json['correct'] == true,
        explanation: (json['explanation'] as String?) ?? '',
        complete: json['complete'] == true,
      );

  final bool correct;
  final String explanation;
  final bool complete;
}
