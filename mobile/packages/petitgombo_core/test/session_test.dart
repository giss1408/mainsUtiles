import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late InMemoryKeyValueStore store;
  late Session session;

  const meBody = {'id': 'u-1', 'phone': '+2250708091011', 'role': 'jobber', 'device_id': 'd'};

  setUp(() {
    adapter = FakeAdapter();
    store = InMemoryKeyValueStore();
    session = Session(ApiClient(dioWith(adapter)), DeviceIdentity(store), store);
  });

  test('signIn signs the challenge, stores the refresh token and returns the user', () async {
    adapter
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'a', 'refresh': 'r'})
      ..reply(200, meBody);
    final me = await session.signIn();
    expect(me.phone, '+2250708091011');
    expect(session.access, 'a');
    expect(await store.read('session.refresh'), 'r');
    final tokenRequest = adapter.requests[1].data as Map;
    expect(tokenRequest['nonce'], 'n-1');
    expect(tokenRequest['signature'], isNotEmpty);
  });

  test('restore without a stored token returns null and makes no call', () async {
    expect(await session.restore(), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('restore uses the stored refresh token', () async {
    await store.write('session.refresh', 'r');
    adapter
      ..reply(200, {'access': 'a2', 'refresh': 'r2'})
      ..reply(200, meBody);
    expect((await session.restore())?.id, 'u-1');
    expect(await store.read('session.refresh'), 'r2');
  });

  test('restore falls back to the device key when the refresh token is rejected', () async {
    await store.write('session.refresh', 'old');
    adapter
      ..reply(401, {'error': 'refresh_invalid'})
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'a', 'refresh': 'r'})
      ..reply(200, meBody);
    expect((await session.restore())?.id, 'u-1');
    expect(await store.read('session.refresh'), 'r');
  });

  test('restore returns null and signs out when the device is revoked', () async {
    await store.write('session.refresh', 'old');
    adapter
      ..reply(401, {'error': 'refresh_invalid'})
      ..reply(200, {'nonce': 'n-1'})
      ..reply(401, {'error': 'device_revoked'});
    expect(await session.restore(), isNull);
    expect(await store.read('session.refresh'), isNull);
    expect(session.access, isNull);
  });

  test('restore rethrows network failures and keeps the stored token', () async {
    await store.write('session.refresh', 'r');
    adapter.offline = true;
    await expectLater(
        session.restore(), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'network')));
    expect(await store.read('session.refresh'), 'r');
  });

  group('authorized', () {
    Future<void> signIn() async {
      adapter
        ..reply(200, {'nonce': 'n-1'})
        ..reply(200, {'access': 'a', 'refresh': 'r'})
        ..reply(200, meBody);
      await session.signIn();
      adapter.requests.clear();
    }

    test('passes the access token to the call', () async {
      await signIn();
      expect(await session.authorized((access) async => 'got $access'), 'got a');
      expect(adapter.requests, isEmpty);
    });

    test('refreshes on 401 and retries once', () async {
      await signIn();
      adapter.reply(200, {'access': 'a2', 'refresh': 'r2'});
      final seen = <String>[];
      final result = await session.authorized((access) async {
        seen.add(access);
        if (access == 'a') throw const ApiError(code: 'token_invalid', message: '', status: 401);
        return 'ok';
      });
      expect(result, 'ok');
      expect(seen, ['a', 'a2']);
      expect(adapter.requests.single.path, '/api/v1/auth/refresh');
      expect(adapter.requests.single.data, {'refresh': 'r'});
      expect(session.access, 'a2');
      expect(await store.read('session.refresh'), 'r2');
    });

    test('rethrows when the refresh is refused', () async {
      await signIn();
      adapter.reply(401, {'error': 'refresh_invalid'});
      await expectLater(
        session.authorized<String>(
          (access) async => throw const ApiError(code: 'token_invalid', message: '', status: 401),
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
    });

    test('other errors are not retried', () async {
      await signIn();
      var calls = 0;
      await expectLater(
        session.authorized<String>((access) async {
          calls++;
          throw const ApiError(code: 'invalid_state', message: 'x', status: 409);
        }),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_state')),
      );
      expect(calls, 1);
      expect(adapter.requests, isEmpty);
    });

    test('two calls that expire together refresh only once', () async {
      await signIn();
      adapter.reply(200, {'access': 'a2', 'refresh': 'r2'});
      Future<String> call() => session.authorized((access) async {
            if (access == 'a') {
              throw const ApiError(code: 'token_invalid', message: '', status: 401);
            }
            return access;
          });
      expect(await Future.wait([call(), call()]), ['a2', 'a2']);
      expect(adapter.requests.map((r) => r.path), ['/api/v1/auth/refresh']);
    });
  });
}
