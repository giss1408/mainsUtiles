// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

const base = '/api/v1/jobber/verification/contacts';

void main() {
  late FakeAdapter adapter;
  late ContactsController controller;
  late int refreshed;

  setUp(() async {
    adapter = FakeAdapter();
    final store = InMemoryKeyValueStore();
    final dio = dioWith(adapter);
    final session = Session(ApiClient(dio), DeviceIdentity(store), store);
    adapter
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(200, {'id': 'u-1', 'phone': '+2250505050505', 'role': 'jobber', 'device_id': 'd'});
    await session.signIn();
    adapter.requests.clear();
    refreshed = 0;
    controller = ContactsController(
      api: VerificationApi(dio, base: VerificationApi.jobberBase),
      session: session,
      refreshChecklist: () async => refreshed++,
    );
  });

  test('load lists the contacts and the maximum', () async {
    adapter.reply(200, {
      'max': 2,
      'contacts': [contactJson(), contactJson(id: 'c-2', status: 'confirmed', awaitingCode: false)],
    });
    await controller.load();
    expect(adapter.requests.single.path, base);
    expect(controller.state.contacts!.map((c) => c.id), ['c-1', 'c-2']);
    expect(controller.state.max, 2);
    expect(controller.state.loading, isFalse);
  });

  test('add posts the name, the normalised phone and the relationship as json', () async {
    adapter
      ..reply(201, contactJson())
      ..reply(200, {
        'max': 2,
        'contacts': [contactJson()]
      });
    final contact =
        await controller.add(name: 'Awa Koné', phone: '01 01 01 01 01', relationship: 'parent');
    expect(contact!.id, 'c-1');
    final request = adapter.requests.first;
    expect(request.method, 'POST');
    expect(request.path, base);
    expect(request.data, {'name': 'Awa Koné', 'phone': '+2250101010101', 'relationship': 'parent'});
    expect(request.headers['Authorization'], 'Bearer acc');
    expect(controller.state.contacts, hasLength(1));
    expect(refreshed, 1);
  });

  test('add refuses an invalid phone without a request', () async {
    expect(await controller.add(name: 'Awa', phone: '123', relationship: 'parent'), isNull);
    expect(adapter.requests, isEmpty);
    expect(controller.state.error, VerificationCopy.contactPhoneInvalid);
  });

  test('replace posts to the replace route of that contact', () async {
    adapter
      ..reply(201, contactJson(id: 'c-9', replaces: 'c-1'))
      ..reply(200, {'max': 2, 'contacts': []});
    final contact =
        await controller.replace('c-1', name: 'Yao', phone: '0102030405', relationship: 'friend');
    expect(contact!.replaces, 'c-1');
    expect(adapter.requests.first.path, '$base/c-1/replace');
    expect(adapter.requests.first.data['phone'], '+2250102030405');
  });

  test('requestCode posts to the code route and reloads the list', () async {
    adapter
      ..reply(200, contactJson())
      ..reply(200, {
        'max': 2,
        'contacts': [contactJson()]
      });
    expect(await controller.requestCode('c-1'), isTrue);
    expect(adapter.requests.first.path, '$base/c-1/code');
    expect(adapter.requests.first.method, 'POST');
  });

  test('confirm success refreshes the list and the checklist', () async {
    adapter
      ..reply(200, contactJson(status: 'confirmed', awaitingCode: false))
      ..reply(200, {
        'max': 2,
        'contacts': [contactJson(status: 'confirmed', awaitingCode: false)],
      });
    expect(await controller.confirm('c-1', '123456'), isTrue);
    expect(adapter.requests.first.path, '$base/c-1/confirm');
    expect(adapter.requests.first.data, {'code': '123456'});
    expect(controller.state.contacts!.single.status, ContactState.confirmed);
    expect(refreshed, 1);
  });

  test('server errors show their French message and keep the list', () async {
    adapter.reply(200, {
      'max': 2,
      'contacts': [contactJson()]
    });
    await controller.load();
    adapter.reply(422, {'error': 'contact_code_invalid', 'message': 'Code incorrect.'});
    expect(await controller.confirm('c-1', '000000'), isFalse);
    expect(controller.state.error, 'Code incorrect.');
    expect(controller.state.contacts, hasLength(1));
    adapter.reply(
        423, {'error': 'contact_locked', 'message': "Trop d'essais. Demandez un nouveau code."});
    expect(await controller.confirm('c-1', '000000'), isFalse);
    expect(controller.state.error, "Trop d'essais. Demandez un nouveau code.");
    expect(refreshed, 0);
  });

  test('offline keeps the state and sets the retry message', () async {
    adapter.offline = true;
    expect(await controller.add(name: 'Awa', phone: '0101010101', relationship: 'parent'), isNull);
    expect(controller.state.error, VerificationCopy.offline);
    expect(controller.state.sending, isFalse);
  });
}
