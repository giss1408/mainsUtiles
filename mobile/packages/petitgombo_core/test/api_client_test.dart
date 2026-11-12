import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late ApiClient api;

  setUp(() {
    adapter = FakeAdapter();
    api = ApiClient(dioWith(adapter));
  });

  const statusBody = {
    'id': 'app-1',
    'status': 'pending',
    'kind': 'new_account',
    'reason': '',
    'response_hours': 24,
  };

  test('apply posts the snake_case body and parses the status', () async {
    adapter.reply(201, statusBody);
    final status = await api.apply(
      phone: '+2250708091011',
      role: AppRole.jobber,
      deviceId: 'dev-1',
      deviceModel: 'Tecno',
      platform: 'android',
      publicKey: 'key',
      clientToken: 'tok',
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/enrolment/applications');
    expect(request.data, {
      'phone': '+2250708091011',
      'role': 'jobber',
      'device_id': 'dev-1',
      'device_model': 'Tecno',
      'platform': 'android',
      'public_key': 'key',
      'client_token': 'tok',
    });
    expect(status.id, 'app-1');
    expect(status.status, 'pending');
    expect(status.responseHours, 24);
    expect(status.reason, isNull);
  });

  test('status and confirm send X-Enrolment-Token', () async {
    adapter.reply(200, {...statusBody, 'status': 'refused', 'reason': 'Injoignable'});
    final status = await api.status('app-1', 'tok');
    expect(adapter.requests[0].path, '/api/v1/enrolment/applications/app-1');
    expect(adapter.requests[0].headers['X-Enrolment-Token'], 'tok');
    expect(status.reason, 'Injoignable');

    adapter.reply(200, {'status': 'completed', 'device_id': 'dev-1'});
    await api.confirm('app-1', 'tok', '123456');
    expect(adapter.requests[1].path, '/api/v1/enrolment/applications/app-1/confirm');
    expect(adapter.requests[1].headers['X-Enrolment-Token'], 'tok');
    expect(adapter.requests[1].data, {'code': '123456'});
  });

  test('422 body becomes ApiError with the server code and message', () async {
    adapter.reply(422, {'error': 'code_invalid', 'message': 'Numéro de confirmation incorrect.'});
    await expectLater(
      api.confirm('app-1', 'tok', '000000'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'code_invalid')
            .having((e) => e.message, 'message', 'Numéro de confirmation incorrect.')
            .having((e) => e.status, 'status', 422),
      ),
    );
  });

  test('connection failure becomes ApiError(code: network)', () async {
    adapter.offline = true;
    await expectLater(
      api.status('app-1', 'tok'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('sign-in calls parse nonce, tokens and me', () async {
    adapter.reply(200, {'nonce': 'n-1'});
    expect(await api.challenge('dev-1'), 'n-1');

    adapter.reply(200, {'access': 'a', 'refresh': 'r'});
    final pair = await api.token('dev-1', 'n-1', 'sig');
    expect(adapter.requests[1].data, {'device_id': 'dev-1', 'nonce': 'n-1', 'signature': 'sig'});
    expect((pair.access, pair.refresh), ('a', 'r'));

    adapter.reply(200, {'access': 'a2', 'refresh': 'r2'});
    expect((await api.refresh('r')).access, 'a2');
    expect(adapter.requests[2].data, {'refresh': 'r'});

    adapter.reply(200, {'id': 'u-1', 'phone': '+2250708091011', 'role': 'jobber', 'device_id': 'dev-1'});
    final me = await api.me('a2');
    expect(adapter.requests[3].headers['Authorization'], 'Bearer a2');
    expect((me.id, me.phone, me.role), ('u-1', '+2250708091011', 'jobber'));
  });
}
