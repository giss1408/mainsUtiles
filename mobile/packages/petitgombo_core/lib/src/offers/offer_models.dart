/// A duty list, durations and a suggested pay, as staff set them up.
class OfferCategory {
  const OfferCategory({
    required this.id,
    required this.name,
    required this.duties,
    required this.durationsMinutes,
    required this.suggestedPayMin,
    required this.suggestedPayMax,
  });

  factory OfferCategory.fromJson(Map<String, dynamic> json) => OfferCategory(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        duties: _strings(json['duties']),
        durationsMinutes: _ints(json['durations_minutes']),
        suggestedPayMin: (json['suggested_pay_min'] as num).toInt(),
        suggestedPayMax: (json['suggested_pay_max'] as num).toInt(),
      );

  final int id;
  final String name;
  final List<String> duties;
  final List<int> durationsMinutes;
  final int suggestedPayMin;
  final int suggestedPayMax;
}

/// The rules the app shows before the server checks them.
class OfferLimits {
  const OfferLimits({
    required this.earliestStart,
    required this.latestEnd,
    required this.minPay,
    required this.maxPay,
    required this.maxDaysAhead,
    required this.noteMaxLength,
  });

  factory OfferLimits.fromJson(Map<String, dynamic> json) => OfferLimits(
        earliestStart: _hourMinute(json['earliest_start'] as String),
        latestEnd: _hourMinute(json['latest_end'] as String),
        minPay: (json['min_pay'] as num).toInt(),
        maxPay: (json['max_pay'] as num).toInt(),
        maxDaysAhead: (json['max_days_ahead'] as num).toInt(),
        noteMaxLength: (json['note_max_length'] as num).toInt(),
      );

  final (int, int) earliestStart;
  final (int, int) latestEnd;
  final int minPay;
  final int maxPay;
  final int maxDaysAhead;
  final int noteMaxLength;
}

enum OfferStatus {
  draft,
  inReview,
  published,
  refused,
  withdrawn,
  closed;

  /// An unknown value reads as "in review": it never invites the author to send it again.
  static OfferStatus parse(String? value) => switch (value) {
        'draft' => OfferStatus.draft,
        'published' => OfferStatus.published,
        'refused' => OfferStatus.refused,
        'withdrawn' => OfferStatus.withdrawn,
        'closed' => OfferStatus.closed,
        _ => OfferStatus.inReview,
      };

  /// The author may withdraw the offer.
  bool get canWithdraw =>
      this == OfferStatus.draft ||
      this == OfferStatus.inReview ||
      this == OfferStatus.published;

  /// The author may make a similar offer from it.
  bool get canCopy =>
      this == OfferStatus.refused ||
      this == OfferStatus.withdrawn ||
      this == OfferStatus.closed;
}

/// One of the householder's own offers, with everything they are allowed to see.
class MyOffer {
  const MyOffer({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.duties,
    required this.startsAt,
    required this.durationMinutes,
    required this.payXof,
    required this.note,
    required this.commune,
    required this.quartier,
    required this.status,
    required this.reason,
  });

  factory MyOffer.fromJson(Map<String, dynamic> json) => MyOffer(
        id: json['id'] as String,
        categoryId: (json['category_id'] as num?)?.toInt() ?? 0,
        categoryName: (json['category_name'] as String?) ?? '',
        duties: _strings(json['duties']),
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        payXof: (json['pay_xof'] as num).toInt(),
        note: (json['note'] as String?) ?? '',
        commune: (json['commune'] as String?) ?? '',
        quartier: (json['quartier'] as String?) ?? '',
        status: OfferStatus.parse(json['status'] as String?),
        reason: (json['reason'] as String?) ?? '',
      );

  final String id;
  final int categoryId;
  final String categoryName;
  final List<String> duties;
  final DateTime startsAt;
  final int durationMinutes;
  final int payXof;
  final String note;
  final String commune;
  final String quartier;
  final OfferStatus status;

  /// Why staff refused or the offer was withdrawn; empty otherwise.
  final String reason;

  MyOffer copyWithStatus(OfferStatus value) => MyOffer(
        id: id,
        categoryId: categoryId,
        categoryName: categoryName,
        duties: duties,
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        payXof: payXof,
        note: note,
        commune: commune,
        quartier: quartier,
        status: value,
        reason: reason,
      );
}

/// What a jobber sees of an offer.
class PublicOffer {
  const PublicOffer({
    required this.id,
    required this.categoryName,
    required this.duties,
    required this.startsAt,
    required this.durationMinutes,
    required this.payXof,
    required this.note,
    required this.commune,
    required this.quartier,
  });

  factory PublicOffer.fromJson(Map<String, dynamic> json) => PublicOffer(
        id: json['id'] as String,
        categoryName: (json['category_name'] as String?) ?? '',
        duties: _strings(json['duties']),
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        payXof: (json['pay_xof'] as num).toInt(),
        note: (json['note'] as String?) ?? '',
        commune: (json['commune'] as String?) ?? '',
        quartier: (json['quartier'] as String?) ?? '',
      );

  final String id;
  final String categoryName;
  final List<String> duties;
  final DateTime startsAt;
  final int durationMinutes;
  final int payXof;
  final String note;
  final String commune;
  final String quartier;
}

/// The values of a draft, as the householder entered them.
class OfferDraft {
  const OfferDraft({
    required this.categoryId,
    required this.duties,
    required this.startsAt,
    required this.durationMinutes,
    required this.payXof,
    required this.note,
  });

  final int categoryId;
  final List<String> duties;
  final DateTime startsAt;
  final int durationMinutes;
  final int payXof;
  final String note;

  /// The start is sent in UTC, which the server expects.
  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'duties': duties,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'pay_xof': payXof,
        'note': note,
      };
}

class MyOffers {
  const MyOffers(
      {required this.canPublish,
      required this.reviewHours,
      required this.offers});

  final bool canPublish;
  final int reviewHours;
  final List<MyOffer> offers;
}

class OfferPage {
  const OfferPage(
      {required this.offers, required this.communes, required this.hasMore});

  final List<PublicOffer> offers;
  final List<String> communes;
  final bool hasMore;
}

List<String> _strings(Object? value) =>
    ((value as List?) ?? const []).map((v) => '$v').toList();

List<int> _ints(Object? value) =>
    ((value as List?) ?? const []).map((v) => (v as num).toInt()).toList();

(int, int) _hourMinute(String value) {
  final parts = value.split(':');
  return (int.parse(parts[0]), int.parse(parts[1]));
}
