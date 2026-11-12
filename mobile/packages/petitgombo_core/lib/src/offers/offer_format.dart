// Amounts, durations and dates as the French apps write them.
//
// Abidjan is at UTC+0 all year, so UTC values are shown as they are.

const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
const _monthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// `3500` becomes `3 500`.
String formatAmount(int amount) {
  final digits = amount.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return '${amount < 0 ? '-' : ''}${groups.join(' ')}';
}

/// `3500` becomes `3 500 FCFA`.
String formatXof(int amount) => '${formatAmount(amount)} FCFA';

/// `120` becomes `2 h`, `150` becomes `2 h 30`, `45` becomes `45 min`.
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest';
}

String _hm(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// `samedi 14 novembre`.
String formatDay(DateTime start) {
  final local = start.toUtc();
  return '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
}

/// `sam. 14 nov. · 08:00 – 11:00`.
String formatWhen(DateTime start, int durationMinutes) {
  final local = start.toUtc();
  final end = local.add(Duration(minutes: durationMinutes));
  return '${_weekdaysShort[local.weekday - 1]} ${local.day} ${_monthsShort[local.month - 1]} · '
      '${_hm(local)} – ${_hm(end)}';
}
