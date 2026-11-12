import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/offer_fixtures.dart';

void main() {
  final limits = OfferLimits.fromJson(limitsJson());

  test('a start at 06:00 with a 2 h duration is allowed', () {
    expect(timeWindowMessage(limits, 6 * 60, 120), isNull);
  });

  test('a start one minute before 06:00 is refused with the hours', () {
    expect(
        timeWindowMessage(limits, 5 * 60 + 59, 120), 'Choisissez un horaire entre 06:00 et 19:00.');
  });

  test('ending exactly at 19:00 is allowed, one minute later is not', () {
    expect(timeWindowMessage(limits, 17 * 60, 120), isNull);
    expect(timeWindowMessage(limits, 17 * 60 + 1, 120), isNotNull);
  });

  test('pay at the limits is allowed, outside them is refused', () {
    expect(payMessage(limits, 1000), isNull);
    expect(payMessage(limits, 100000), isNull);
    expect(payMessage(limits, 999), 'Indiquez un montant entre 1 000 et 100 000 FCFA.');
    expect(payMessage(limits, 100001), isNotNull);
    expect(payMessage(limits, null), isNotNull);
  });
}
