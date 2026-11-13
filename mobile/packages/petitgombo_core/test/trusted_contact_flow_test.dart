import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';
import 'verification_screens_test.dart' show Harness, settle, tapText;

Map<String, dynamic> listJson(List<Map<String, dynamic>> contacts, {int max = 2}) =>
    {'max': max, 'contacts': contacts};

/// Opens the flow; [first] is what the contact list returns on load.
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
                  .push(MaterialPageRoute<void>(builder: (_) => const TrustedContactFlow())),
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

Future<void> fillWho(
  WidgetTester tester, {
  String name = 'Awa Koné',
  String phone = '01 01 01 01 01',
}) async {
  await tester.enterText(find.byKey(const Key('contact-name')), name);
  await tester.enterText(find.byKey(const Key('contact-phone')), phone);
  await settle(tester);
}

Map<String, dynamic> confirmedContact({String id = 'c-1'}) =>
    contactJson(id: id, status: 'confirmed', awaitingCode: false);

void main() {
  testWidgets('an empty list offers to add a person; the form has the privacy note',
      (tester) async {
    await pumpFlow(tester, listJson([]));
    expect(find.text('Personnes de confiance'), findsOneWidget);
    await tapText(tester, 'Ajouter une personne');
    expect(find.text('Étape 1 sur 2'), findsOneWidget);
    expect(find.textContaining('Notre équipe envoie un message WhatsApp'), findsOneWidget);
    for (final label in ['Parent', 'Famille', 'Ami(e)', 'Autre']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('an empty name and an invalid phone show errors and send nothing', (tester) async {
    final h = await pumpFlow(tester, listJson([]));
    await tapText(tester, 'Ajouter une personne');
    await tapText(tester, 'Parent');
    expect(find.text('Indique le nom de la personne.'), findsOneWidget);
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
    await fillWho(tester, phone: '123');
    await tapText(tester, 'Parent');
    expect(find.text('Indique le nom de la personne.'), findsNothing);
    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
    expect(h.adapter.requests, hasLength(1)); // only the first load
  });

  testWidgets('a full run adds, takes the code and shows the contact as Confirmé', (tester) async {
    final h = await pumpFlow(tester, listJson([]));
    await tapText(tester, 'Ajouter une personne');
    await fillWho(tester);
    h.adapter
      ..reply(201, contactJson())
      ..reply(200, listJson([contactJson()]))
      ..reply(200, jobberChecklistJson());
    await tapText(tester, 'Parent');
    expect(find.text('Étape 2 sur 2'), findsOneWidget);
    expect(find.textContaining('Notre équipe envoie un code par WhatsApp'), findsOneWidget);
    final post = h.adapter.requests[1];
    expect(post.path, '/api/v1/jobber/verification/contacts');
    expect(post.data, {'name': 'Awa Koné', 'phone': '+2250101010101', 'relationship': 'parent'});

    await tester.enterText(find.byKey(const Key('contact-code')), '123456');
    h.adapter
      ..reply(200, confirmedContact())
      ..reply(200, listJson([confirmedContact()]))
      ..reply(
          200, jobberChecklistJson(contact: contactStepJson(status: 'confirmed', confirmed: 1)));
    await tapText(tester, 'Confirmer');
    expect(
        h.adapter.requests.firstWhere((r) => r.path.endsWith('/confirm')).data, {'code': '123456'});
    expect(find.text('Personnes de confiance'), findsOneWidget);
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(find.text('Confirmé'), findsOneWidget);
  });

  testWidgets('a wrong code shows its message and keeps the field', (tester) async {
    final h = await pumpFlow(tester, listJson([contactJson(awaitingCode: false)]));
    await tapText(tester, 'Saisir le code');
    await tester.enterText(find.byKey(const Key('contact-code')), '000000');
    h.adapter.reply(422, {'error': 'contact_code_invalid', 'message': 'Code incorrect.'});
    await tapText(tester, 'Confirmer');
    expect(find.text('Code incorrect.'), findsOneWidget);
    expect(find.text('000000'), findsOneWidget);
    expect(find.text('Étape 2 sur 2'), findsOneWidget);
  });

  testWidgets('a pending contact shows its state and can ask for a new code', (tester) async {
    final h = await pumpFlow(tester, listJson([contactJson()]));
    expect(find.text("En attente d'envoi du code"), findsOneWidget);
    expect(find.text('Saisir le code'), findsNothing);
    h.adapter
      ..reply(200, contactJson())
      ..reply(200, listJson([contactJson()]));
    await tapText(tester, 'Demander un nouveau code');
    expect(h.adapter.requests[1].path, '/api/v1/jobber/verification/contacts/c-1/code');
  });

  testWidgets('Changer on a confirmed contact says it stays, and both show until the swap',
      (tester) async {
    final h = await pumpFlow(tester, listJson([confirmedContact()]));
    await tapText(tester, 'Changer');
    expect(find.textContaining('reste en place'), findsOneWidget);
    await fillWho(tester, name: 'Yao', phone: '01 02 03 04 05');
    h.adapter
      ..reply(201, contactJson(id: 'c-2', replaces: 'c-1'))
      ..reply(200, listJson([confirmedContact(), contactJson(id: 'c-2', replaces: 'c-1')]))
      ..reply(200, jobberChecklistJson());
    await tapText(tester, 'Ami(e)');
    expect(h.adapter.requests[1].path, '/api/v1/jobber/verification/contacts/c-1/replace');
    expect(find.text('Étape 2 sur 2'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Awa Koné'), findsNWidgets(2)); // both contacts in the fixture share a name
    expect(find.text('Confirmé'), findsOneWidget);
  });

  testWidgets('a contact already being replaced cannot be changed again', (tester) async {
    await pumpFlow(
      tester,
      listJson([confirmedContact(), contactJson(id: 'c-2', replaces: 'c-1')]),
    );
    expect(find.text('Changer'), findsOneWidget); // only the replacement
  });

  testWidgets('there is no remove action anywhere', (tester) async {
    await pumpFlow(tester, listJson([confirmedContact(), contactJson(id: 'c-2')]));
    for (final word in ['Retirer', 'Supprimer', 'Effacer']) {
      expect(find.textContaining(word), findsNothing);
    }
  });

  testWidgets('the add button disappears at the maximum, a replacement takes no slot',
      (tester) async {
    await pumpFlow(
      tester,
      listJson([
        confirmedContact(),
        contactJson(id: 'c-2'),
      ]),
    );
    expect(find.text('Ajouter une personne'), findsNothing);
  });

  testWidgets('the add button stays while a replacement is the second row', (tester) async {
    await pumpFlow(
      tester,
      listJson([confirmedContact(), contactJson(id: 'c-2', replaces: 'c-1')]),
    );
    expect(find.text('Ajouter une personne'), findsOneWidget);
  });

  testWidgets('does not overflow at 320dp and text scale 2', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpFlow(tester, listJson([confirmedContact(), contactJson(id: 'c-2')]));
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Changer');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Parent');
    expect(tester.takeException(), isNull);
  });
}
