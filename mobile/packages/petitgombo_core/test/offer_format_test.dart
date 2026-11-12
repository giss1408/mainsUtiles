import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

void main() {
  test('amounts are grouped by thousands and carry the currency', () {
    expect(formatXof(3500), '3 500 FCFA');
    expect(formatXof(100000), '100 000 FCFA');
    expect(formatXof(999), '999 FCFA');
  });

  test('durations read in hours', () {
    expect(formatDuration(120), '2 h');
    expect(formatDuration(150), '2 h 30');
    expect(formatDuration(480), '8 h');
    expect(formatDuration(45), '45 min');
  });

  test('a day and its time window are written in French', () {
    // Saturday 14 November 2026, 08:00 UTC is 08:00 in Abidjan (UTC+0).
    final start = DateTime.utc(2026, 11, 14, 8);
    expect(formatDay(start), 'samedi 14 novembre');
    expect(formatWhen(start, 180), 'sam. 14 nov. · 08:00 – 11:00');
  });

  test('a start at 06:00 on a Sunday in January', () {
    final start = DateTime.utc(2027, 1, 3, 6);
    expect(formatWhen(start, 120), 'dim. 3 janv. · 06:00 – 08:00');
  });
}
