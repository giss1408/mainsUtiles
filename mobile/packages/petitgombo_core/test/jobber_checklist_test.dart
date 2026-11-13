import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';
import 'verification_screens_test.dart' show Harness, settle, tapText;

Future<Harness> pumpJobber(WidgetTester tester, Map<String, dynamic> first) async {
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
      child: MaterialApp(theme: buildAppTheme(), home: const ChecklistScreen()),
    ),
  );
  await settle(tester);
  return h;
}

void main() {
  testWidgets('a jobber sees the four steps, in tu', (tester) async {
    final h = await pumpJobber(tester, jobberChecklistJson());
    expect(h.adapter.requests.first.path, '/api/v1/jobber/verification');
    expect(find.text('Vérifie ton compte'), findsOneWidget);
    expect(find.text('Quelques étapes pour pouvoir postuler.'), findsOneWidget);
    expect(find.text("Pièce d'identité"), findsOneWidget);
    expect(find.text('Garant'), findsOneWidget);
    expect(find.text('Personne de confiance'), findsOneWidget);
    expect(find.text('Consignes de sécurité'), findsOneWidget);
    expect(find.text('Commencer'), findsNWidgets(4));
    expect(find.text('Justificatif de domicile'), findsNothing);
    expect(find.text('Position du domicile'), findsNothing);
    expect(find.text('Vérification de votre compte'), findsNothing);
  });

  testWidgets('the guarantor status is shown in words', (tester) async {
    await pumpJobber(
      tester,
      jobberChecklistJson(guarantor: {'status': 'refused', 'reason': 'Facture illisible.'}),
    );
    expect(find.text('Facture illisible.'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
  });

  testWidgets('the identity flow asks in tu and shows the privacy note in tu', (tester) async {
    await pumpJobber(tester, jobberChecklistJson());
    await tester.tap(find.text('Commencer').first);
    await settle(tester);
    expect(find.text('Quel document vas-tu utiliser ?'), findsOneWidget);
    expect(find.textContaining('Tes photos sont chiffrées'), findsOneWidget);
    expect(find.textContaining('Vos photos'), findsNothing);
  });

  testWidgets('at J1 the jobber sees the verified note in tu', (tester) async {
    await pumpJobber(tester, allConfirmed());
    expect(find.text('Compte vérifié'), findsOneWidget);
    expect(find.text('Tu pourras bientôt postuler aux offres.'), findsOneWidget);
    expect(find.text('Commencer'), findsNothing);
    expect(find.text('Quelques étapes pour pouvoir postuler.'), findsNothing);
  });

  testWidgets('a card added after J1 shows Nouvelle carte à lire', (tester) async {
    await pumpJobber(
      tester,
      allConfirmed(
          briefing: briefingStepJson(status: 'confirmed', answered: 3, total: 4, newCards: 1)),
    );
    expect(find.text('Nouvelle carte à lire'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('a contact waiting for its code offers Continuer and opens the contacts',
      (tester) async {
    final h = await pumpJobber(
      tester,
      jobberChecklistJson(contact: contactStepJson(status: 'in_progress', pending: 1)),
    );
    expect(find.text('En attente de confirmation.'), findsOneWidget);
    h.adapter.reply(200, {
      'max': 2,
      'contacts': [contactJson()]
    });
    await tapText(tester, 'Continuer');
    expect(find.text('Personnes de confiance'), findsOneWidget);
    expect(find.text("En attente d'envoi du code"), findsOneWidget);
  });

  testWidgets('the briefing step shows progress and opens the cards', (tester) async {
    final h = await pumpJobber(
      tester,
      jobberChecklistJson(briefing: briefingStepJson(status: 'in_progress', answered: 1)),
    );
    expect(find.text('1 carte sur 3'), findsOneWidget);
    h.adapter.reply(200, {
      'progress': briefingStepJson(status: 'in_progress', answered: 1),
      'cards': [cardJson(answered: true), cardJson(id: 'k-2', title: 'Deux')],
    });
    await tapText(tester, 'Continuer');
    expect(find.text('Carte 2 sur 2'), findsOneWidget);
  });

  testWidgets('a confirmed contact offers Modifier, never a way to remove', (tester) async {
    await pumpJobber(
      tester,
      jobberChecklistJson(contact: contactStepJson(status: 'confirmed', confirmed: 1)),
    );
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.textContaining('Retirer'), findsNothing);
  });
  testWidgets('the four step cards do not overflow at 320dp and text scale 2', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpJobber(
      tester,
      jobberChecklistJson(
        guarantor: {'status': 'refused', 'reason': 'Facture illisible, reprenez la photo.'},
        contact: contactStepJson(status: 'in_progress', pending: 1),
        briefing: briefingStepJson(status: 'in_progress', answered: 1),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> allConfirmed({Map<String, dynamic>? briefing}) {
  const done = {'status': 'confirmed', 'reason': ''};
  return jobberChecklistJson(
    tier: 'J1',
    identity: done,
    guarantor: done,
    contact: contactStepJson(status: 'confirmed', confirmed: 1),
    briefing: briefing ?? briefingStepJson(status: 'confirmed', answered: 3),
  );
}
