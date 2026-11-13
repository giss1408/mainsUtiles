// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

const base = '/api/v1/jobber/verification/briefing';

void main() {
  late FakeAdapter adapter;
  late BriefingController controller;
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
    controller = BriefingController(
      api: VerificationApi(dio, base: VerificationApi.jobberBase),
      session: session,
      refreshChecklist: () async => refreshed++,
    );
  });

  test('load fills the cards and the progress', () async {
    adapter.reply(200, {
      'progress': briefingStepJson(status: 'in_progress', answered: 1),
      'cards': [cardJson(answered: true), cardJson(id: 'k-2')],
    });
    await controller.load();
    expect(adapter.requests.single.path, base);
    expect(controller.state.cards!.map((c) => c.id), ['k-1', 'k-2']);
    expect(controller.state.cards!.first.answered, isTrue);
    expect(controller.state.progress!.answered, 1);
  });

  test('a wrong answer returns the explanation and refreshes nothing', () async {
    adapter.reply(200, {'correct': false, 'explanation': 'Parce que.', 'complete': false});
    final answer = await controller.answer('k-1', 0);
    expect(answer!.correct, isFalse);
    expect(answer.explanation, 'Parce que.');
    expect(adapter.requests.single.path, '$base/k-1/answer');
    expect(adapter.requests.single.data, {'choice': 0});
    expect(refreshed, 0);
  });

  test('a correct answer marks the card; the last one refreshes the checklist', () async {
    adapter.reply(200, {
      'progress': briefingStepJson(),
      'cards': [cardJson(), cardJson(id: 'k-2')],
    });
    await controller.load();
    adapter.reply(200, {'correct': true, 'explanation': 'Oui.', 'complete': false});
    await controller.answer('k-1', 1);
    expect(controller.state.cards!.first.answered, isTrue);
    expect(controller.state.cards!.last.answered, isFalse);
    expect(refreshed, 0);

    adapter.reply(200, {'correct': true, 'explanation': 'Oui.', 'complete': true});
    final last = await controller.answer('k-2', 1);
    expect(last!.complete, isTrue);
    expect(controller.state.cards!.every((c) => c.answered), isTrue);
    expect(refreshed, 1);
  });

  test('errors show the French message and offline the retry message', () async {
    adapter.reply(400, {'error': 'choice_invalid', 'message': 'Choix invalide.'});
    expect(await controller.answer('k-1', 9), isNull);
    expect(controller.state.error, 'Choix invalide.');
    adapter.offline = true;
    expect(await controller.answer('k-1', 1), isNull);
    expect(controller.state.error, VerificationCopy.offline);
  });
}
