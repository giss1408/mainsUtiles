import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';
import 'verification_screens_test.dart' show Harness, settle;

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
  testWidgets('a jobber sees identity and guarantor, in tu', (tester) async {
    final h = await pumpJobber(tester, jobberChecklistJson());
    expect(h.adapter.requests.first.path, '/api/v1/jobber/verification');
    expect(find.text('Vérifie ton compte'), findsOneWidget);
    expect(find.text('Deux étapes pour pouvoir postuler.'), findsOneWidget);
    expect(find.text("Pièce d'identité"), findsOneWidget);
    expect(find.text('Garant'), findsOneWidget);
    expect(find.text('Commencer'), findsNWidgets(2));
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
    const confirmed = {'status': 'confirmed', 'reason': ''};
    await pumpJobber(
      tester,
      jobberChecklistJson(tier: 'J1', identity: confirmed, guarantor: confirmed),
    );
    expect(find.text('Compte vérifié'), findsOneWidget);
    expect(find.text('Tu pourras bientôt postuler aux offres.'), findsOneWidget);
    expect(find.text('Commencer'), findsNothing);
    expect(find.text('Deux étapes pour pouvoir postuler.'), findsNothing);
  });
}
