// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';

const base = '/api/v1';

CapturedPhoto proof() => CapturedPhoto(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]),
      capturedAt: DateTime.utc(2026, 11, 13, 10),
    );

void main() {
  late FakeAdapter adapter;
  late BookingController controller;
  late ApplicationsController jobber;
  late int changed;

  setUp(() async {
    adapter = FakeAdapter();
    final store = InMemoryKeyValueStore();
    final dio = dioWith(adapter);
    final session = Session(ApiClient(dio), DeviceIdentity(store), store);
    adapter
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(
          200, {'id': 'u-1', 'phone': '+2250505050505', 'role': 'householder', 'device_id': 'd'});
    await session.signIn();
    adapter.requests.clear();
    changed = 0;
    controller = BookingController(
      offerId: 'o-1',
      api: ApplicationsApi(dio),
      session: session,
      onChanged: () async => changed++,
    );
    jobber = ApplicationsController(api: ApplicationsApi(dio), session: session);
  });

  test('load fills the booking detail', () async {
    adapter.reply(200, bookingDetailJson());
    await controller.load();
    expect(adapter.requests.single.path, '$base/my-offers/o-1/booking');
    expect(controller.state.detail!.methods, hasLength(2));
    expect(controller.state.loading, isFalse);
  });

  test('submitProof sends the multipart fields, then reloads and tells the offers list', () async {
    adapter
      ..reply(201, {'id': 'p-1', 'status': 'submitted'})
      ..reply(
          200,
          bookingDetailJson(
              status: 'payment_review', payment: {'status': 'submitted', 'reason': ''}));
    final sent =
        await controller.submitProof(methodId: 1, reference: 'WAVE-123456', screenshot: proof());
    expect(sent, isTrue);
    final upload = adapter.requests.first;
    expect(upload.path, '$base/my-offers/o-1/booking/payment');
    final form = upload.data as FormData;
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['method_id'], '1');
    expect(fields['reference'], 'WAVE-123456');
    expect(fields['captured_at'], '2026-11-13T10:00:00.000Z');
    expect(form.files.single.key, 'screenshot');
    expect(controller.state.detail!.status, 'payment_review');
    expect(changed, 1);
  });

  test('a refused proof shows the server message and keeps nothing', () async {
    adapter.reply(
        400, {'error': 'reference_invalid', 'message': 'Indiquez la référence de la transaction.'});
    final sent = await controller.submitProof(methodId: 1, reference: 'ab', screenshot: proof());
    expect(sent, isFalse);
    expect(controller.state.error, 'Indiquez la référence de la transaction.');
    expect(controller.state.sending, isFalse);
  });

  test('cancel sends the reason, reloads and tells the offers list', () async {
    adapter
      ..reply(200, {'id': 'b-1', 'status': 'cancelled'})
      ..reply(404, {'error': 'not_found', 'message': 'Réservation introuvable.'});
    expect(await controller.cancel('Changement de plan'), isTrue);
    expect(adapter.requests.first.path, '$base/my-offers/o-1/booking/cancel');
    expect(adapter.requests.first.data, {'reason': 'Changement de plan'});
    expect(changed, 1);
  });

  test('the photo is fetched as bytes on demand', () async {
    adapter.reply(
        200,
        bookingDetailJson(
            status: 'confirmed', jobber: {'full_name': 'Awa Koné', 'has_photo': true}));
    await controller.load();
    expect(controller.state.photo, isNull);
    adapter.replyBytes(200, [0xff, 0xd8, 0xff]);
    await controller.loadPhoto();
    expect(adapter.requests.last.path, '$base/my-offers/o-1/booking/photo');
    expect(controller.state.photo, isNotNull);
  });

  test('the jobber reads the address and cancels', () async {
    adapter.reply(200, addressJson());
    final address = await jobber.address('b-1');
    expect(adapter.requests.single.path, '$base/my-bookings/b-1/address');
    expect(address!.commune, 'Cocody');
    adapter
      ..reply(200, {'id': 'b-1', 'status': 'cancelled'})
      ..reply(200, {'results': []})
      ..reply(200, {'results': []});
    expect(await jobber.cancelBooking('b-1', 'Malade'), isTrue);
    expect(adapter.requests[1].path, '$base/my-bookings/b-1/cancel');
  });

  test('a refused address shows the server text', () async {
    adapter.reply(409, {
      'error': 'address_not_yet',
      'message': "L'adresse sera communiquée quelques heures avant le début."
    });
    expect(await jobber.address('b-1'), isNull);
    expect(jobber.state.error, "L'adresse sera communiquée quelques heures avant le début.");
  });

  test('offline shows the retry message', () async {
    adapter.offline = true;
    await controller.load();
    expect(controller.state.error, OfferCopy.offline);
  });
}
