// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';

const path = '/api/v1/my-offers/o-1/applicants';

void main() {
  late FakeAdapter adapter;
  late ApplicantsController controller;
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
    controller = ApplicantsController(
      offerId: 'o-1',
      api: ApplicationsApi(dio),
      session: session,
      onChanged: () async => changed++,
    );
  });

  test('load lists the applicants', () async {
    adapter.reply(200, {
      'results': [applicantJson(), applicantJson(id: 'a-2', name: 'Koffi')]
    });
    await controller.load();
    expect(adapter.requests.single.path, path);
    expect(controller.state.applicants!.map((a) => a.firstName), ['Awa', 'Koffi']);
  });

  test('accept returns the booking, reloads the list and tells the offers list', () async {
    adapter
      ..reply(201, acceptedJson())
      ..reply(200, {'results': []});
    final booking = await controller.accept('a-1');
    expect(booking!.jobberFirstName, 'Awa');
    expect(adapter.requests.first.path, '$path/a-1/accept');
    expect(controller.state.applicants, isEmpty);
    expect(changed, 1);
  });

  test('invalid_state on accept reloads the list and shows the message', () async {
    adapter
      ..reply(409, {'error': 'invalid_state', 'message': 'Action impossible maintenant.'})
      ..reply(200, {
        'results': [applicantJson(id: 'a-2')]
      });
    expect(await controller.accept('a-1'), isNull);
    expect(controller.state.error, 'Action impossible maintenant.');
    expect(controller.state.applicants!.single.id, 'a-2');
    expect(changed, 1);
    expect(controller.state.sending, isFalse);
  });

  test('offline shows the retry message', () async {
    adapter.offline = true;
    await controller.load();
    expect(controller.state.error, OfferCopy.offline);
  });
}
