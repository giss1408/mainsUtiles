import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late VerificationApi api;

  setUp(() {
    adapter = FakeAdapter();
    api = VerificationApi(dioWith(adapter));
  });

  test('checklist parses statuses, communes and tier', () async {
    adapter.reply(
      200,
      checklistJson(
        identity: {'status': 'refused', 'reason': 'Photo floue'},
        address: {
          'status': 'confirmed',
          'reason': '',
          'commune': 'Cocody',
          'quartier': 'Angré',
          'expires_at': '2027-11-12T10:00:00Z',
        },
        homeLocation: {'status': 'in_review', 'reason': ''},
      ),
    );
    final checklist = await api.checklist('acc');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/v1/verification');
    expect(request.headers['Authorization'], 'Bearer acc');
    expect(checklist.tier, 'H0');
    expect(checklist.verified, isFalse);
    expect(checklist.reviewHours, 24);
    expect(checklist.communes, ['Cocody', 'Yopougon']);
    expect(checklist.identity.status, StepStatus.refused);
    expect(checklist.identity.reason, 'Photo floue');
    expect(checklist.address.status, StepStatus.confirmed);
    expect(checklist.address.commune, 'Cocody');
    expect(checklist.address.quartier, 'Angré');
    expect(checklist.address.expiresAt, DateTime.utc(2027, 11, 12, 10));
    expect(checklist.homeLocation.status, StepStatus.inReview);
  });

  test('unknown and missing statuses are read safely', () {
    expect(StepStatus.parse('not_started'), StepStatus.notStarted);
    expect(StepStatus.parse('expired'), StepStatus.expired);
    expect(StepStatus.parse('something_new'), StepStatus.submitted);
    expect(VerificationChecklist.fromJson(checklistJson(tier: 'H1')).verified, isTrue);
  });

  test('submitIdentity posts multipart with three jpeg parts and the document type', () async {
    adapter.reply(201, checklistJson(identity: {'status': 'submitted', 'reason': ''}));
    final checklist = await api.submitIdentity(
      'acc',
      documentType: 'cni',
      front: photo(1, position: (5.36, -3.98)),
      back: photo(2),
      selfie: photo(3, at: DateTime.utc(2026, 11, 12, 9, 30)),
    );

    expect(checklist.identity.status, StepStatus.submitted);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/verification/identity');
    expect(request.headers['Authorization'], 'Bearer acc');
    final form = request.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['document_type'], 'cni');
    expect(fields['captured_at'], '2026-11-12T09:30:00.000Z');
    expect(fields['lat'], '5.36');
    expect(fields['lng'], '-3.98');
    expect(form.files.map((f) => f.key), ['front', 'back', 'selfie']);
    expect(form.files.map((f) => f.value.filename), ['front.jpg', 'back.jpg', 'selfie.jpg']);
    for (final file in form.files) {
      expect(file.value.contentType.toString(), 'image/jpeg');
    }
    expect(form.files.first.value.length, photo(1).bytes.length);
  });

  test('submitAddress posts the photo, commune and quartier without a position', () async {
    adapter.reply(201, checklistJson());
    await api.submitAddress(
      'acc',
      documentType: 'facture_eau',
      photo: photo(4),
      commune: 'Yopougon',
      quartier: 'Niangon Nord',
    );
    final form = adapter.requests.single.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(adapter.requests.single.path, '/api/v1/verification/address');
    expect(fields['document_type'], 'facture_eau');
    expect(fields['commune'], 'Yopougon');
    expect(fields['quartier'], 'Niangon Nord');
    expect(fields.containsKey('lat'), isFalse);
    expect(form.files.single.key, 'photo');
  });

  test('413 becomes ApiError(code: photo_too_large) with the French message', () async {
    adapter.reply(
        413, {'error': 'photo_too_large', 'message': 'Photo trop lourde. Reprenez la photo.'});
    await expectLater(
      api.submitAddress('acc',
          documentType: 'facture_eau', photo: photo(4), commune: 'Cocody', quartier: 'x'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'photo_too_large')
            .having((e) => e.message, 'message', 'Photo trop lourde. Reprenez la photo.'),
      ),
    );
  });

  test('recordHomeLocation sends lat, lng, accuracy_m, mock_location, captured_at', () async {
    adapter.reply(201, checklistJson(homeLocation: {'status': 'submitted', 'reason': ''}));
    final checklist = await api.recordHomeLocation(
      'acc',
      DevicePosition(
        lat: 5.3599,
        lng: -3.9871,
        accuracyM: 12.4,
        mocked: true,
        capturedAt: DateTime.utc(2026, 11, 12, 9),
      ),
    );
    expect(checklist.homeLocation.status, StepStatus.submitted);
    expect(adapter.requests.single.path, '/api/v1/verification/home-location');
    expect(adapter.requests.single.data, {
      'lat': 5.3599,
      'lng': -3.9871,
      'accuracy_m': 12.4,
      'mock_location': true,
      'captured_at': '2026-11-12T09:00:00.000Z',
    });
  });

  test('photo bytes are never part of an error text', () {
    final captured =
        CapturedPhoto(bytes: Uint8List.fromList([1, 2, 3]), capturedAt: DateTime.utc(2026));
    expect(captured.toString(), isNot(contains('1, 2, 3')));
  });
}
