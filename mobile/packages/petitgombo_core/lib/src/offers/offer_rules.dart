import 'offer_format.dart';
import 'offer_models.dart';

// Checks the app makes before sending, with the limits the server returns.
// The server checks the same rules again and has the last word.

String _hm(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Null when a start at [startMinutes] (minutes after midnight, Abidjan time) and a
/// [durationMinutes] long offer fits between the earliest start and the latest end.
String? timeWindowMessage(OfferLimits limits, int startMinutes, int durationMinutes) {
  final earliest = limits.earliestStart.$1 * 60 + limits.earliestStart.$2;
  final latest = limits.latestEnd.$1 * 60 + limits.latestEnd.$2;
  if (startMinutes >= earliest && startMinutes + durationMinutes <= latest) return null;
  return 'Choisissez un horaire entre ${_hm(earliest)} et ${_hm(latest)}.';
}

/// Null when [pay] is a whole amount within the limits.
String? payMessage(OfferLimits limits, int? pay) {
  if (pay != null && pay >= limits.minPay && pay <= limits.maxPay) return null;
  return 'Indiquez un montant entre ${formatAmount(limits.minPay)} et ${formatXof(limits.maxPay)}.';
}
