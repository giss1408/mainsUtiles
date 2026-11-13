import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';

void main() {
  test('a booking detail parses methods, amounts, deadline and the first name', () {
    final detail = BookingDetail.fromJson(bookingDetailJson());
    expect(detail.status, 'accepted');
    expect(detail.amountXof, 3500);
    expect(detail.methods.map((m) => m.providerLabel), ['Wave', 'MTN MoMo']);
    expect(detail.methods.first.number, '+2250101010101');
    expect(detail.jobberFirstName, 'Awa');
    expect(detail.jobberFullName, isNull);
    expect(detail.hasPhoto, isFalse);
    expect(detail.payment, isNull);
    expect(detail.cancellable, isTrue);
    expect(detail.payDeadline.isUtc, isFalse);
  });

  test('after confirmation the detail carries the full name and the photo flag', () {
    final detail = BookingDetail.fromJson(bookingDetailJson(
      status: 'confirmed',
      jobber: {'full_name': 'Awa Koné', 'has_photo': true},
      payment: {'status': 'confirmed', 'reason': ''},
    ));
    expect(detail.jobberFullName, 'Awa Koné');
    expect(detail.hasPhoto, isTrue);
    expect(detail.payment!.status, 'confirmed');
  });

  test('a refused payment keeps its reason', () {
    final detail = BookingDetail.fromJson(
      bookingDetailJson(payment: {'status': 'refused', 'reason': 'Montant faux'}),
    );
    expect(detail.payment!.refused, isTrue);
    expect(detail.payment!.reason, 'Montant faux');
  });

  test('a jobber booking knows when its address comes and the payment state', () {
    final booking = JobberBooking.fromJson(jobberBookingJson());
    expect(booking.payment, 'pending');
    expect(booking.addressAvailableFrom, DateTime.utc(2026, 11, 14, 5).toLocal());
  });

  test('a released address parses', () {
    final address = ReleasedAddress.fromJson(addressJson());
    expect((address.latitude, address.longitude), (5.3599, -3.9871));
    expect(address.quartier, 'Angré');
  });
}
