// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

class FakeApi implements ApiClient {
  int applyCalls = 0;
  String? appliedPhone;
  String serverStatus = 'pending';
  ApiError? applyError;
  ApiError? statusError;
  ApiError? confirmError;
  final List<String> confirmedCodes = [];

  EnrolmentStatus _status() =>
      EnrolmentStatus(id: 'app-1', status: serverStatus, reason: null, responseHours: 24);

  @override
  Future<EnrolmentStatus> apply({
    required String phone,
    required AppRole role,
    required String deviceId,
    required String deviceModel,
    required String platform,
    required String publicKey,
    required String clientToken,
  }) async {
    applyCalls++;
    appliedPhone = phone;
    if (applyError != null) throw applyError!;
    return _status();
  }

  @override
  Future<EnrolmentStatus> status(String id, String clientToken) async {
    if (statusError != null) throw statusError!;
    return _status();
  }

  @override
  Future<void> confirm(String id, String clientToken, String code) async {
    confirmedCodes.add(code);
    if (confirmError != null) throw confirmError!;
    serverStatus = 'completed';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSession implements Session {
  int signIns = 0;
  ApiError? signInError;

  @override
  Future<Me> signIn() async {
    signIns++;
    if (signInError != null) throw signInError!;
    return const Me(id: 'u-1', phone: '+2250708091011', role: 'jobber');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const network = ApiError(code: 'network', message: '');

void main() {
  late FakeApi api;
  late FakeSession session;
  late InMemoryKeyValueStore store;
  late EnrolmentController controller;

  EnrolmentController build() => EnrolmentController(
        api: api,
        identity: DeviceIdentity(store),
        session: session,
        store: store,
        role: AppRole.jobber,
        deviceModel: 'Tecno',
        platform: 'android',
      );

  setUp(() {
    api = FakeApi();
    session = FakeSession();
    store = InMemoryKeyValueStore();
    controller = build();
  });

  test('invalid phone fails without calling the API', () async {
    await controller.submitPhone('12345');
    final state = controller.state;
    expect(state, isA<EnrolmentFailure>());
    expect((state as EnrolmentFailure).message, 'Numéro de téléphone invalide.');
    expect(state.previous, isA<EnrolmentInitial>());
    expect(api.applyCalls, 0);
  });

  test('valid phone goes to EnrolmentPending(24) and stores the application id', () async {
    await controller.submitPhone('07 08 09 10 11');
    expect(api.appliedPhone, '+2250708091011');
    expect(controller.state, isA<EnrolmentPending>().having((s) => s.responseHours, 'hours', 24));
    expect(await store.read('enrolment.application_id'), 'app-1');
  });

  test('resume restores EnrolmentAwaitingCode from the stored id', () async {
    await controller.submitPhone('0708091011');
    api.serverStatus = 'awaiting_code';
    final reopened = build();
    await reopened.resume();
    expect(reopened.state, isA<EnrolmentAwaitingCode>());
  });

  test('resume without a stored application is EnrolmentInitial', () async {
    await controller.resume();
    expect(controller.state, isA<EnrolmentInitial>());
  });

  test('server statuses map to their states', () async {
    await controller.submitPhone('0708091011');
    final expected = <String, Matcher>{
      'held': isA<EnrolmentHeld>(),
      'refused': isA<EnrolmentRefused>(),
      'locked': isA<EnrolmentLocked>(),
      'expired': isA<EnrolmentExpired>(),
    };
    for (final entry in expected.entries) {
      api.serverStatus = entry.key;
      await controller.refresh();
      expect(controller.state, entry.value, reason: entry.key);
    }
  });

  test('wrong code stays in EnrolmentAwaitingCode with the server message', () async {
    await controller.submitPhone('0708091011');
    api.serverStatus = 'awaiting_code';
    await controller.refresh();
    api.confirmError =
        const ApiError(code: 'code_invalid', message: 'Numéro de confirmation incorrect.', status: 422);
    await controller.submitCode('000000');
    expect(
      controller.state,
      isA<EnrolmentAwaitingCode>()
          .having((s) => s.errorMessage, 'error', 'Numéro de confirmation incorrect.'),
    );
    expect(session.signIns, 0);
  });

  test('correct code signs in and ends in EnrolmentDone', () async {
    await controller.submitPhone('0708091011');
    api.serverStatus = 'awaiting_code';
    await controller.refresh();
    await controller.submitCode('123456');
    expect(api.confirmedCodes, ['123456']);
    expect(session.signIns, 1);
    expect(controller.state, isA<EnrolmentDone>().having((s) => s.me.role, 'role', 'jobber'));
  });

  test('locked response ends in EnrolmentLocked', () async {
    await controller.submitPhone('0708091011');
    api.confirmError = const ApiError(code: 'locked', message: 'Trop d\'essais.', status: 423);
    await controller.submitCode('000000');
    expect(controller.state, isA<EnrolmentLocked>());
  });

  test('network error keeps the stored application id', () async {
    await controller.submitPhone('0708091011');
    api.confirmError = network;
    await controller.submitCode('123456');
    final state = controller.state;
    expect(state, isA<EnrolmentFailure>());
    expect((state as EnrolmentFailure).message, 'Pas de connexion. Réessayez.');
    expect(state.previous, isA<EnrolmentAwaitingCode>());
    expect(await store.read('enrolment.application_id'), 'app-1');
  });

  test('network error while applying returns to the phone screen state', () async {
    api.applyError = network;
    await controller.submitPhone('0708091011');
    final state = controller.state as EnrolmentFailure;
    expect(state.message, 'Pas de connexion. Réessayez.');
    expect(state.previous, isA<EnrolmentInitial>());
    expect(await store.read('enrolment.application_id'), isNull);
  });

  test('an application the server no longer knows sends the user back to the start', () async {
    await controller.submitPhone('0708091011');
    api.statusError = const ApiError(code: 'forbidden', message: '', status: 404);
    await controller.refresh();
    expect(controller.state, isA<EnrolmentInitial>());
    expect(await store.read('enrolment.application_id'), isNull);
  });

  test('startOver clears the application id but keeps the device id', () async {
    final identity = DeviceIdentity(store);
    await controller.submitPhone('0708091011');
    final deviceId = await identity.deviceId();
    await controller.startOver();
    expect(controller.state, isA<EnrolmentInitial>());
    expect(await store.read('enrolment.application_id'), isNull);
    expect(await identity.deviceId(), deviceId);
  });
}
