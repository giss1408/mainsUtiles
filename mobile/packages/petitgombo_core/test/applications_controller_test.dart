// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';

const base = '/api/v1';

void main() {
  late FakeAdapter adapter;
  late ApplicationsController controller;

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
    controller = ApplicationsController(api: ApplicationsApi(dio), session: session);
  });

  test('load fills the applications and the bookings', () async {
    adapter
      ..reply(200, {
        'results': [applicationItemJson()]
      })
      ..reply(200, {
        'results': [jobberBookingJson()]
      });
    await controller.load();
    expect(adapter.requests.map((r) => r.path), ['$base/my-applications', '$base/my-bookings']);
    expect(controller.state.applications!.single.id, 'a-1');
    expect(controller.state.bookings!.single.id, 'b-1');
    expect(controller.state.loading, isFalse);
  });

  test('apply sends the message and reports success', () async {
    adapter.reply(201, {
      'id': 'a-9',
      'offer_id': 'o-1',
      'status': 'pending',
      'created_at': '2026-11-12T10:00:00Z',
    });
    final application = await controller.apply('o-1', 'Bonjour');
    expect(application!.id, 'a-9');
    expect(adapter.requests.single.path, '$base/offers/o-1/apply');
    expect(adapter.requests.single.data, {'message': 'Bonjour'});
    expect(controller.state.sending, isFalse);
  });

  test('a refused message shows the server text and returns null', () async {
    adapter.reply(400, {
      'error': 'message_contact_details',
      'message': 'Ne mets pas de numéro ni de contact dans ton message.',
    });
    expect(await controller.apply('o-1', '07 08 09 10 11'), isNull);
    expect(controller.state.error, 'Ne mets pas de numéro ni de contact dans ton message.');
    expect(controller.state.sending, isFalse);
  });

  test('withdraw updates the row', () async {
    adapter
      ..reply(200, {
        'results': [applicationItemJson()]
      })
      ..reply(200, {'results': []})
      ..reply(200, {
        'id': 'a-1',
        'offer_id': 'o-1',
        'status': 'withdrawn',
        'created_at': '2026-11-12T10:00:00Z',
      });
    await controller.load();
    expect(await controller.withdraw('a-1'), isTrue);
    expect(adapter.requests.last.path, '$base/my-applications/a-1/withdraw');
    expect(controller.state.applications!.single.status, ApplicationStatus.withdrawn);
  });

  test('offline shows the retry message', () async {
    adapter.offline = true;
    await controller.load();
    expect(controller.state.error, OfferCopy.offline);
    expect(controller.state.loading, isFalse);
  });
}
