// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late InMemoryKeyValueStore store;
  late Session session;
  late FakePositionReader reader;
  late VerificationController controller;

  setUp(() async {
    adapter = FakeAdapter();
    store = InMemoryKeyValueStore();
    final dio = dioWith(adapter);
    session = Session(ApiClient(dio), DeviceIdentity(store), store);
    adapter
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(
          200, {'id': 'u-1', 'phone': '+2250505050505', 'role': 'householder', 'device_id': 'd'});
    await session.signIn();
    adapter.requests.clear();
    reader = FakePositionReader();
    controller =
        VerificationController(api: VerificationApi(dio), session: session, position: reader);
  });

  Future<bool> sendIdentity() => controller.sendIdentity(
        documentType: 'cni',
        front: photo(1),
        back: photo(2),
        selfie: photo(3),
      );

  test('load fills the checklist', () async {
    adapter.reply(200, checklistJson());
    expect(controller.state.checklist, isNull);
    await controller.load();
    expect(controller.state.checklist!.identity.status, StepStatus.notStarted);
    expect(controller.state.loading, isFalse);
    expect(controller.state.error, isNull);
  });

  test('load failure keeps the previous checklist and reports the problem', () async {
    adapter.reply(200, checklistJson(tier: 'H1'));
    await controller.load();
    adapter.offline = true;
    await controller.load();
    expect(controller.state.checklist!.verified, isTrue);
    expect(controller.state.error, VerificationCopy.offline);
  });

  test('sendIdentity success replaces the checklist and returns true', () async {
    adapter.reply(201, checklistJson(identity: {'status': 'submitted', 'reason': ''}));
    expect(await sendIdentity(), isTrue);
    expect(controller.state.checklist!.identity.status, StepStatus.submitted);
    expect(controller.state.sending, isFalse);
    expect(controller.state.error, isNull);
  });

  test('network failure keeps the state, sets the retry message and returns false', () async {
    adapter.reply(200, checklistJson());
    await controller.load();
    adapter.offline = true;
    expect(await sendIdentity(), isFalse);
    expect(controller.state.error, 'Pas de connexion. Vos photos sont gardées. Réessayez.');
    expect(controller.state.checklist!.identity.status, StepStatus.notStarted);
    expect(controller.state.sending, isFalse);

    adapter.offline = false;
    adapter.reply(201, checklistJson(identity: {'status': 'submitted', 'reason': ''}));
    expect(await sendIdentity(), isTrue);
    expect(controller.state.error, isNull);
  });

  test('a server refusal shows the server message', () async {
    adapter.reply(409, {'error': 'invalid_state', 'message': 'Cette étape est déjà envoyée.'});
    expect(await sendIdentity(), isFalse);
    expect(controller.state.error, 'Cette étape est déjà envoyée.');
  });

  test('refused step can be sent again', () async {
    adapter.reply(200, checklistJson(identity: {'status': 'refused', 'reason': 'Photo floue'}));
    await controller.load();
    expect(controller.state.checklist!.identity.reason, 'Photo floue');
    adapter.reply(201, checklistJson(identity: {'status': 'submitted', 'reason': ''}));
    expect(await sendIdentity(), isTrue);
    expect(controller.state.checklist!.identity.status, StepStatus.submitted);
    expect(controller.state.checklist!.identity.reason, isEmpty);
  });

  test('sendAddress posts and updates the checklist', () async {
    adapter.reply(
      201,
      checklistJson(
        address: {
          'status': 'submitted',
          'reason': '',
          'commune': 'Cocody',
          'quartier': 'Angré',
          'expires_at': null,
        },
      ),
    );
    final ok = await controller.sendAddress(
      documentType: 'facture_eau',
      photo: photo(4),
      commune: 'Cocody',
      quartier: 'Angré',
    );
    expect(ok, isTrue);
    expect(controller.state.checklist!.address.commune, 'Cocody');
  });

  test('recordHome reads the position then posts it', () async {
    adapter.reply(201, checklistJson(homeLocation: {'status': 'submitted', 'reason': ''}));
    expect(await controller.recordHome(), isTrue);
    expect(reader.reads, 1);
    expect((adapter.requests.single.data as Map)['accuracy_m'], 12.4);
    expect(controller.state.checklist!.homeLocation.status, StepStatus.submitted);
  });

  test('recordHome maps permissionDenied to the French message', () async {
    reader.failure = CaptureFailure.permissionDenied;
    expect(await controller.recordHome(), isFalse);
    expect(controller.state.error, 'Autorisez la localisation pour continuer.');
    expect(controller.state.captureFailure, CaptureFailure.permissionDenied);
    expect(adapter.requests, isEmpty);

    reader.failure = CaptureFailure.unavailable;
    await controller.recordHome();
    expect(controller.state.error, 'Position indisponible. Activez la localisation et réessayez.');

    reader.failure = null;
    adapter.reply(201, checklistJson());
    expect(await controller.recordHome(), isTrue);
    expect(controller.state.captureFailure, isNull);
  });

  test('an inaccurate position shows the server advice', () async {
    adapter.reply(422, {
      'error': 'location_inaccurate',
      'message':
          "Position trop imprécise. Rapprochez-vous d'une fenêtre ou sortez, puis réessayez.",
    });
    expect(await controller.recordHome(), isFalse);
    expect(controller.state.error, startsWith('Position trop imprécise.'));
  });

  test('an expired access token is refreshed once and the call retried', () async {
    adapter
      ..reply(401, {'error': 'token_invalid'})
      ..reply(200, {'access': 'acc2', 'refresh': 'ref2'})
      ..reply(200, checklistJson());
    await controller.load();
    expect(adapter.requests.map((r) => r.path), [
      '/api/v1/verification',
      '/api/v1/auth/refresh',
      '/api/v1/verification',
    ]);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer acc2');
    expect(controller.state.checklist, isNotNull);
    expect(await store.read('session.refresh'), 'ref2');
  });

  test('a session that cannot be renewed asks the user to sign in again', () async {
    adapter
      ..reply(401, {'error': 'token_invalid'})
      ..reply(401, {'error': 'refresh_invalid'});
    await controller.load();
    expect(controller.state.error, VerificationCopy.sessionExpired);
  });
}
