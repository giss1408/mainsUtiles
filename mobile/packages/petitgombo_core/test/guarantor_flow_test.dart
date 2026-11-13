import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';
import 'verification_screens_test.dart' show Harness, settle, tapText, takeAndUse;

Future<Harness> pumpFlow(WidgetTester tester) async {
  final h = Harness();
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
                  .push(MaterialPageRoute<void>(builder: (_) => const GuarantorFlow())),
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

Future<void> fillWho(WidgetTester tester,
    {String name = 'Awa Koné', String phone = '07 07 07 07 07'}) async {
  await tester.enterText(find.byKey(const Key('guarantor-name')), name);
  await tester.enterText(find.byKey(const Key('guarantor-phone')), phone);
  await settle(tester);
}

void main() {
  testWidgets('shows progress and the privacy note on step 1', (tester) async {
    await pumpFlow(tester);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
    expect(
      find.textContaining('On appelle ton garant pour confirmer.'),
      findsOneWidget,
    );
    for (final label in ['Parent', 'Famille', 'Propriétaire', 'Autre']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('empty name and invalid phone show their errors and do not advance', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Parent');
    expect(find.text('Indique le nom de ton garant.'), findsOneWidget);
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);

    await fillWho(tester, phone: '123');
    await tapText(tester, 'Parent');
    expect(find.text('Indique le nom de ton garant.'), findsNothing);
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
  });

  testWidgets('a full run posts one multipart request with a normalised phone and pops',
      (tester) async {
    final h = await pumpFlow(tester);
    await fillWho(tester);
    await tapText(tester, 'Propriétaire');
    expect(find.text('Étape 2 sur 4'), findsOneWidget);
    await tapText(tester, "Facture d'eau");
    expect(find.text('Étape 3 sur 4'), findsOneWidget);
    await takeAndUse(tester);
    expect(h.camera.asked, [PhotoKind.guarantorBill]);
    expect(find.text('Étape 4 sur 4'), findsOneWidget);

    h.adapter.reply(201, jobberChecklistJson(guarantor: {'status': 'submitted', 'reason': ''}));
    await tapText(tester, 'Envoyer');
    expect(h.adapter.requests, hasLength(1));
    final request = h.adapter.requests.single;
    expect(request.path, '/api/v1/jobber/verification/guarantor');
    final form = request.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['guarantor_phone'], '+2250707070707');
    expect(fields['guarantor_name'], 'Awa Koné');
    expect(fields['relationship'], 'landlord');
    expect(fields['document_type'], 'facture_eau');
    expect(form.files, hasLength(1));
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('back keeps typed text and removes the last photo', (tester) async {
    final h = await pumpFlow(tester);
    await fillWho(tester);
    await tapText(tester, 'Parent');
    await tapText(tester, "Facture d'électricité");
    await takeAndUse(tester);
    expect(find.text('Étape 4 sur 4'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('Étape 3 sur 4'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Étape 2 sur 4'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Étape 1 sur 4'), findsOneWidget);
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(find.text('07 07 07 07 07'), findsOneWidget);
    expect(h.adapter.requests, isEmpty);
  });

  testWidgets('an offline error keeps the photo and shows Réessayer', (tester) async {
    final h = await pumpFlow(tester);
    await fillWho(tester);
    await tapText(tester, 'Autre');
    await tapText(tester, 'Certificat de résidence');
    await takeAndUse(tester);

    h.adapter.offline = true;
    await tapText(tester, 'Envoyer');
    expect(find.text('Pas de connexion. Vos photos sont gardées. Réessayez.'), findsOneWidget);
    expect(find.text('Étape 4 sur 4'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    h.adapter
      ..offline = false
      ..reply(201, jobberChecklistJson(guarantor: {'status': 'submitted', 'reason': ''}));
    await tapText(tester, 'Réessayer');
    expect(h.camera.asked, hasLength(1));
    expect((h.adapter.requests.last.data as FormData).files, hasLength(1));
  });

  testWidgets('does not overflow at 320dp and text scale 2', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final h = await pumpFlow(tester);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Parent');
    expect(tester.takeException(), isNull);
    await fillWho(tester);
    await tapText(tester, 'Parent');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Abonnement prépayé');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Prendre la photo');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Utiliser cette photo');
    expect(tester.takeException(), isNull);
    expect(h.camera.asked, hasLength(1));
  });
}
