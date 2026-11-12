import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';
import 'package:staff/src/staff_api.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late StaffApi api;

  setUp(() {
    adapter = FakeAdapter();
    api = StaffApi(dioWith(adapter));
  });

  test('send returns the WhatsApp Uri from whatsapp_url', () async {
    adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=x'});
    final uri = await api.send('acc', 'a1');
    expect(uri, Uri.parse('https://wa.me/2250708091011?text=x'));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/staff/enrolments/a1/send');
    expect(request.headers['Authorization'], 'Bearer acc');
  });

  test('enrolments passes the status query and parses items', () async {
    adapter.reply(200, {
      'count': 1,
      'next': null,
      'previous': null,
      'results': [
        itemJson(status: 'approved', flags: ['device_multiple_numbers']),
      ],
    });
    final items = await api.enrolments('acc', status: 'approved');
    expect(adapter.requests.single.queryParameters, {'status': 'approved'});
    final item = items.single;
    expect(item.id, 'a1');
    expect(item.phone, '+2250708091011');
    expect(item.role, 'jobber');
    expect(item.kind, 'new_account');
    expect(item.status, 'approved');
    expect(item.flags, ['device_multiple_numbers']);
    expect(item.deviceModel, 'Tecno Spark');
    expect(item.platform, 'android');
    expect(item.integrityVerdict, 'unchecked');
    expect(item.createdAt, DateTime.utc(2026, 11, 12, 10));
    expect(item.reason, isNull);
  });

  test('423 becomes ApiError(code: locked)', () async {
    adapter.reply(423, {'error': 'locked'});
    await expectLater(
      api.login(username: 'agent', password: 'pw', deviceId: 'd', nonce: 'n', signature: 's'),
      throwsA(isA<ApiError>()
          .having((e) => e.code, 'code', 'locked')
          .having((e) => e.status, 'status', 423)),
    );
  });

  test('registerDevice sends the phone description and returns its status', () async {
    adapter.reply(201, {'status': 'pending'});
    final status = await api.registerDevice(
      username: 'agent',
      password: 'pw',
      deviceId: 'd1',
      deviceModel: 'Samsung A15',
      platform: 'android',
      publicKey: 'key',
    );
    expect(status, 'pending');
    expect(adapter.requests.single.path, '/api/v1/staff/devices');
    expect(adapter.requests.single.data, {
      'username': 'agent',
      'password': 'pw',
      'device_id': 'd1',
      'device_model': 'Samsung A15',
      'platform': 'android',
      'public_key': 'key',
    });
  });

  test('refuse sends the reason and parses the updated item', () async {
    adapter.reply(200, itemJson(status: 'refused', reason: 'Injoignable'));
    final updated = await api.refuse('acc', 'a1', 'Injoignable');
    expect(adapter.requests.single.path, '/api/v1/staff/enrolments/a1/refuse');
    expect(adapter.requests.single.data, {'reason': 'Injoignable'});
    expect(updated.status, 'refused');
    expect(updated.reason, 'Injoignable');
  });
}
