import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

void main() {
  test('local and international forms normalise', () {
    for (final raw in [
      '07 08 09 10 11',
      '0708091011',
      '+2250708091011',
      '00225 0708091011',
      '+225 07-08-09-10-11',
    ]) {
      expect(normaliseIvorianPhone(raw), '+2250708091011', reason: raw);
    }
  });

  test('invalid input returns null', () {
    for (final raw in ['', '12345', '+33612345678', 'abc', '07080910111']) {
      expect(normaliseIvorianPhone(raw), isNull, reason: raw);
    }
  });
}
