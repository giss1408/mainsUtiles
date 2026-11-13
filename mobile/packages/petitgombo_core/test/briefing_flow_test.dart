import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';
import 'verification_screens_test.dart' show Harness, settle, tapText;

Map<String, dynamic> briefingJson(List<Map<String, dynamic>> cards, {int answered = 0}) => {
      'progress': briefingStepJson(answered: answered, total: cards.length),
      'cards': cards,
    };

Future<Harness> pumpFlow(WidgetTester tester, Map<String, dynamic> first) async {
  final h = Harness()..adapter.reply(200, first);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(h.adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        photoCaptureProvider.overrideWithValue(h.camera),
        positionReaderProvider.overrideWithValue(h.position),
        appRoleProvider.overrideWithValue(AppRole.jobber),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const BriefingFlow())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  return h;
}

Map<String, dynamic> answer({bool correct = true, bool complete = false}) =>
    {'correct': correct, 'explanation': 'Parce que.', 'complete': complete};

void main() {
  testWidgets('shows the first unanswered card with its progress, skipping answered ones',
      (tester) async {
    await pumpFlow(
      tester,
      briefingJson([
        cardJson(title: 'Un', answered: true),
        cardJson(id: 'k-2', title: 'Deux'),
        cardJson(id: 'k-3', title: 'Trois'),
      ], answered: 1),
    );
    expect(find.text('Carte 2 sur 3'), findsOneWidget);
    expect(find.text('Deux'), findsOneWidget);
    expect(find.text('Que fais-tu ?'), findsOneWidget);
    expect(find.text('Je préviens'), findsOneWidget);
  });

  testWidgets('a wrong answer shows the explanation and Réessayer on the same card',
      (tester) async {
    final h = await pumpFlow(tester, briefingJson([cardJson(title: 'Un'), cardJson(id: 'k-2')]));
    h.adapter.reply(200, answer(correct: false));
    await tapText(tester, 'Je reste');
    expect(h.adapter.requests.last.path, '/api/v1/jobber/verification/briefing/k-1/answer');
    expect(h.adapter.requests.last.data, {'choice': 0});
    expect(find.text('Parce que.'), findsOneWidget);
    expect(find.text('Bien vu.'), findsNothing);
    await tapText(tester, 'Réessayer');
    expect(find.text('Carte 1 sur 2'), findsOneWidget);
    expect(find.text('Je préviens'), findsOneWidget);
    expect(find.text('Parce que.'), findsNothing);
  });

  testWidgets('a correct answer moves on and the last one ends the briefing', (tester) async {
    final h = await pumpFlow(
        tester, briefingJson([cardJson(title: 'Un'), cardJson(id: 'k-2', title: 'Deux')]));
    h.adapter.reply(200, answer());
    await tapText(tester, 'Je préviens');
    expect(find.text('Bien vu.'), findsOneWidget);
    await tapText(tester, 'Continuer');
    expect(find.text('Carte 2 sur 2'), findsOneWidget);
    expect(find.text('Deux'), findsOneWidget);

    h.adapter
      ..reply(200, answer(complete: true))
      ..reply(
          200,
          jobberChecklistJson(
              briefing: briefingStepJson(status: 'confirmed', answered: 2, total: 2)));
    await tapText(tester, 'Je préviens');
    await tapText(tester, 'Continuer');
    expect(find.text('Briefing terminé'), findsOneWidget);
    await tapText(tester, 'Terminer');
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('with every card already answered the end screen is shown', (tester) async {
    await pumpFlow(tester, briefingJson([cardJson(answered: true)], answered: 1));
    expect(find.text('Briefing terminé'), findsOneWidget);
  });

  testWidgets('no cards shows the empty state', (tester) async {
    await pumpFlow(tester, briefingJson([]));
    expect(find.text('Rien à lire pour le moment.'), findsOneWidget);
  });

  testWidgets('an error while answering is shown and the card stays', (tester) async {
    final h = await pumpFlow(tester, briefingJson([cardJson()]));
    h.adapter.offline = true;
    await tapText(tester, 'Je reste');
    expect(find.text(VerificationCopy.offline), findsOneWidget);
    expect(find.text('Que fais-tu ?'), findsOneWidget);
  });

  testWidgets('does not overflow at 320dp and text scale 2', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final h = await pumpFlow(tester, briefingJson([cardJson(), cardJson(id: 'k-2')]));
    expect(tester.takeException(), isNull);
    h.adapter.reply(200, answer(correct: false));
    await tapText(tester, 'Je reste');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Réessayer');
    h.adapter.reply(200, answer());
    await tapText(tester, 'Je préviens');
    expect(tester.takeException(), isNull);
  });
}
