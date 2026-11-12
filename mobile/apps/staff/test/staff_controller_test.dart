import 'package:flutter_test/flutter_test.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_copy.dart';

import 'support/fixtures.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());

  test('first sign-in registers the device then reports device_pending', () async {
    h.adapter.reply(201, {'status': 'pending'});
    await h.controller.signIn('agent', 'pw');

    expect(h.controller.state.stage, StaffStage.devicePending);
    final request = h.adapter.requests.single;
    expect(request.path, '/api/v1/staff/devices');
    final body = request.data as Map;
    expect(body['username'], 'agent');
    expect(body['password'], 'pw');
    expect(body['device_model'], 'Samsung A15');
    expect(body['platform'], 'android');
    expect(body['device_id'], isNotEmpty);
    expect(body['public_key'], isNotEmpty);
    expect(h.session.access, isNull);
  });

  test('sign-in on an active device stores tokens in memory and loads the queue', () async {
    h.queueSignIn(pending: [itemJson()]);
    await h.controller.signIn('agent', 'pw');

    final state = h.controller.state;
    expect(state.stage, StaffStage.queue);
    expect(state.me!.username, 'agent');
    expect(state.items!.single.id, 'a1');
    expect(h.session.access, 'acc');
    expect(h.adapter.requests.map((r) => r.path), [
      '/api/v1/staff/devices',
      '/api/v1/auth/challenge',
      '/api/v1/staff/auth/login',
      '/api/v1/staff/me',
      '/api/v1/staff/enrolments',
    ]);
    final login = h.adapter.requests[2].data as Map;
    expect(login['nonce'], 'n1');
    expect(login['signature'], isNotEmpty);
    // Neither the password nor the tokens are written to storage.
    expect(h.store.values.values, isNot(contains('pw')));
    expect(h.store.values.values, isNot(contains('acc')));
    expect(h.store.values.values, isNot(contains('ref')));
  });

  test('a revoked phone registers again under a new identity', () async {
    h.adapter
      ..reply(200, {'status': 'revoked'})
      ..reply(201, {'status': 'pending'});
    await h.controller.signIn('agent', 'pw');

    expect(h.controller.state.stage, StaffStage.devicePending);
    final ids = h.adapter.requests.map((r) => (r.data as Map)['device_id']).toList();
    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
  });

  test('wrong password stays on the login screen with the French message', () async {
    h.adapter.reply(401, {'error': 'bad_credentials'});
    await h.controller.signIn('agent', 'nope');
    expect(h.controller.state.stage, StaffStage.login);
    expect(h.controller.state.error, StaffCopy.badCredentials);
    expect(h.controller.state.busy, isFalse);
  });

  test('a locked account shows the fifteen-minute message', () async {
    h.adapter.reply(423, {'error': 'locked'});
    await h.controller.signIn('agent', 'pw');
    expect(h.controller.state.error, 'Trop d\'essais. Réessayez dans 15 minutes.');
  });

  test('approve moves the item out of the pending list', () async {
    h.queueSignIn(pending: [itemJson(), itemJson(id: 'b2')]);
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson());
    await h.controller.open(h.controller.state.items!.first);

    h.adapter.reply(200, itemJson(status: 'approved'));
    await h.controller.approve();

    expect(h.adapter.requests.last.path, '/api/v1/staff/enrolments/a1/approve');
    expect(h.controller.state.items!.map((i) => i.id), ['b2']);
    expect(h.controller.state.selected!.status, 'approved');
    expect(h.controller.state.error, isNull);
  });

  test('a refused action keeps the item and shows the server message', () async {
    h.queueSignIn(pending: [itemJson()]);
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson());
    await h.controller.open(h.controller.state.items!.first);

    h.adapter.reply(
        409, {'error': 'invalid_state', 'message': 'Cette demande ne peut plus être modifiée.'});
    await h.controller.approve();

    expect(h.controller.state.error, 'Cette demande ne peut plus être modifiée.');
    expect(h.controller.state.selected!.status, 'pending');
    expect(h.controller.state.stage, StaffStage.queue);
  });

  test('401 during an action signs the user out', () async {
    h.queueSignIn(pending: [itemJson()]);
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson());
    await h.controller.open(h.controller.state.items!.first);

    h.adapter
      ..reply(401, {'error': 'token_invalid'})
      ..reply(401, {'error': 'refresh_invalid'});
    await h.controller.approve();

    expect(h.adapter.requests.last.path, '/api/v1/auth/refresh');
    expect(h.adapter.requests.last.data, {'refresh': 'ref'});
    expect(h.controller.state.stage, StaffStage.login);
    expect(h.controller.state.selected, isNull);
    expect(h.controller.state.error, StaffCopy.sessionExpired);
    expect(h.session.access, isNull);
  });

  test('an expired access token is renewed once and the action is retried', () async {
    h.queueSignIn(pending: [itemJson()]);
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson());
    await h.controller.open(h.controller.state.items!.first);
    final before = h.adapter.requests.length;

    h.adapter
      ..reply(401, {'error': 'token_invalid'})
      ..reply(200, {'access': 'acc2', 'refresh': 'ref2'})
      ..reply(200, itemJson(status: 'approved'));
    await h.controller.approve();

    final paths = h.adapter.requests.skip(before).map((r) => r.path).toList();
    expect(paths, [
      '/api/v1/staff/enrolments/a1/approve',
      '/api/v1/auth/refresh',
      '/api/v1/staff/enrolments/a1/approve',
    ]);
    expect(h.adapter.requests.last.headers['Authorization'], 'Bearer acc2');
    expect(h.controller.state.stage, StaffStage.queue);
    expect(h.controller.state.selected!.status, 'approved');
    expect(h.session.access, 'acc2');
    expect(h.store.values.values, isNot(contains('ref2')));
  });

  test('two calls that expire together renew the token only once', () async {
    h.queueSignIn();
    await h.controller.signIn('agent', 'pw');
    final before = h.adapter.requests.length;

    // A refresh token presented twice makes the server revoke the phone's tokens.
    h.adapter.reply(200, {'access': 'acc2', 'refresh': 'ref2'});
    final results = await Future.wait([h.session.refresh(), h.session.refresh()]);
    expect(results, [true, true]);
    expect(h.adapter.requests.skip(before).map((r) => r.path), ['/api/v1/auth/refresh']);
  });

  test('a network failure while renewing keeps the session', () async {
    h.queueSignIn(pending: [itemJson()]);
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson());
    await h.controller.open(h.controller.state.items!.first);

    h.adapter.reply(401, {'error': 'token_invalid'});
    h.adapter.offlineAfterReplies = true;
    await h.controller.approve();

    expect(h.controller.state.stage, StaffStage.queue);
    expect(h.controller.state.error, StaffCopy.offline);
    expect(h.session.access, 'acc');
  });

  test('changing tab loads that status', () async {
    h.queueSignIn();
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, {
      'results': [itemJson(status: 'approved')],
    });
    await h.controller.selectTab('approved');
    expect(h.adapter.requests.last.queryParameters, {'status': 'approved'});
    expect(h.controller.state.items!.single.status, 'approved');
  });

  test('send returns the link and marks the item as sent without keeping the link', () async {
    h.queueSignIn();
    await h.controller.signIn('agent', 'pw');
    h.adapter.reply(200, itemJson(status: 'approved'));
    await h.controller.open(item(status: 'approved'));

    h.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=x'});
    final uri = await h.controller.send();

    expect(uri, Uri.parse('https://wa.me/2250708091011?text=x'));
    expect(h.controller.state.selected!.status, 'code_sent');
  });

  test('age is written in French', () {
    final created = DateTime.utc(2026, 11, 12, 10);
    expect(StaffCopy.age(created, DateTime.utc(2026, 11, 12, 10, 0, 20)), "à l'instant");
    expect(StaffCopy.age(created, DateTime.utc(2026, 11, 12, 10, 5)), 'il y a 5 min');
    expect(StaffCopy.age(created, DateTime.utc(2026, 11, 12, 13)), 'il y a 3 h');
    expect(StaffCopy.age(created, DateTime.utc(2026, 11, 14, 11)), 'il y a 2 j');
  });
}
