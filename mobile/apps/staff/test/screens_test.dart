import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';
import 'package:staff/main.dart';
import 'package:staff/src/providers.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

class Screen {
  final adapter = FakeAdapter();
  final opened = <Uri>[];
  bool whatsAppInstalled = true;
  late final StaffController controller;
}

/// Shows the app already signed in, in [state].
Future<Screen> pumpSignedIn(
  WidgetTester tester, {
  List<EnrolmentItem> items = const [],
  EnrolmentItem? selected,
  List<String> permissions = allPermissions,
}) async {
  final screen = Screen();
  final api = StaffApi(dioWith(screen.adapter));
  screen.controller = StaffController(
    api: api,
    session: SignedInSession(api),
    initial: StaffState(
      stage: StaffStage.queue,
      me: StaffMe(id: 'u1', username: 'agent', permissions: permissions),
      items: items,
      selected: selected,
    ),
  );
  await tester.pumpWidget(
    buildApp(
      overrides: [
        staffControllerProvider.overrideWith((ref) => screen.controller),
        urlOpenerProvider.overrideWithValue((uri) async {
          screen.opened.add(uri);
          return screen.whatsAppInstalled;
        }),
      ],
    ),
  );
  await tester.pump();
  return screen;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('login shows the French error for bad credentials', (tester) async {
    final adapter = FakeAdapter()..reply(401, {'error': 'bad_credentials'});
    await tester.pumpWidget(
      buildApp(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      ),
    );
    expect(find.text('Identifiant'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'agent');
    await tester.enterText(find.byType(TextField).at(1), 'nope');
    await tester.tap(find.text('Se connecter'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);

    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('login does nothing while a field is empty', (tester) async {
    final adapter = FakeAdapter();
    await tester.pumpWidget(
      buildApp(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'agent');
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('device pending screen explains and returns to login', (tester) async {
    final adapter = FakeAdapter();
    final api = StaffApi(dioWith(adapter));
    final controller = StaffController(
      api: api,
      session: SignedInSession(api),
      initial: const StaffState(stage: StaffStage.devicePending),
    );
    await tester.pumpWidget(
      buildApp(overrides: [staffControllerProvider.overrideWith((ref) => controller)]),
    );
    expect(find.text("Appareil en attente d'activation par un administrateur."), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('queue shows three tabs and the empty state', (tester) async {
    await pumpSignedIn(tester);
    expect(find.text("Demandes d'enrôlement"), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('À envoyer'), findsOneWidget);
    expect(find.text('Envoyées'), findsOneWidget);
    expect(find.text('Aucune demande.'), findsOneWidget);
  });

  testWidgets('tapping a tab loads that list', (tester) async {
    final screen = await pumpSignedIn(tester);
    screen.adapter.reply(200, {
      'results': [itemJson(status: 'approved')],
    });
    await tester.tap(find.text('À envoyer'));
    await settle(tester);
    expect(screen.adapter.requests.single.queryParameters, {'status': 'approved'});
    expect(find.text('+225 07 08 09 10 11'), findsOneWidget);
    expect(find.textContaining('Mini-jobber'), findsOneWidget);
  });

  testWidgets('flagged request shows the warning and the French flag text', (tester) async {
    final screen = await pumpSignedIn(
      tester,
      items: [
        item(flags: ['device_multiple_numbers']),
        item(id: 'b2'),
      ],
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    screen.adapter.reply(200, itemJson(flags: ['device_multiple_numbers']));
    await tester.tap(find.text('+225 07 08 09 10 11').first);
    await settle(tester);
    expect(find.text('Cet appareil a demandé plusieurs numéros.'), findsOneWidget);
    expect(find.text('Approuver'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.text('Mettre en attente'), findsOneWidget);
  });

  testWidgets('refuse dialog keeps the button disabled until a reason is typed', (tester) async {
    final screen = await pumpSignedIn(tester, selected: item());
    await tester.ensureVisible(find.text('Refuser'));
    await tester.tap(find.text('Refuser'));
    await settle(tester);

    FilledButton confirm() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmer'));
    expect(find.text('Motif'), findsOneWidget);
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Numéro injoignable');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);

    screen.adapter.reply(200, itemJson(status: 'refused', reason: 'Numéro injoignable'));
    await tester.tap(find.text('Confirmer'));
    await settle(tester);
    expect(screen.adapter.requests.single.path, '/api/v1/staff/enrolments/a1/refuse');
    expect(screen.adapter.requests.single.data, {'reason': 'Numéro injoignable'});
    expect(find.text('Refusée'), findsOneWidget);
    expect(find.text('Approuver'), findsNothing);
  });

  testWidgets('Envoyer par WhatsApp opens the returned URL once and does not display it',
      (tester) async {
    final screen = await pumpSignedIn(tester, selected: item(status: 'approved'));
    screen.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=x'});
    await tester.ensureVisible(find.text('Envoyer par WhatsApp'));
    await tester.tap(find.text('Envoyer par WhatsApp'));
    await settle(tester);

    expect(screen.opened, [Uri.parse('https://wa.me/2250708091011?text=x')]);
    expect(find.textContaining('wa.me'), findsNothing);
    expect(find.text('Envoyez uniquement depuis le WhatsApp officiel.'), findsOneWidget);
    expect(find.text('Renvoyer par WhatsApp'), findsOneWidget);
  });

  testWidgets('a phone without WhatsApp gets a clear message', (tester) async {
    final screen = await pumpSignedIn(tester, selected: item(status: 'code_sent'));
    screen.whatsAppInstalled = false;
    screen.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=x'});
    await tester.ensureVisible(find.text('Renvoyer par WhatsApp'));
    await tester.tap(find.text('Renvoyer par WhatsApp'));
    await settle(tester);
    expect(find.text("WhatsApp n'est pas installé sur cet appareil."), findsOneWidget);
  });

  testWidgets('send button is hidden without the send_enrolment_code permission', (tester) async {
    await pumpSignedIn(tester,
        selected: item(status: 'approved'), permissions: ['review_enrolment']);
    expect(find.text('Envoyer par WhatsApp'), findsNothing);
    expect(find.text('Approuvée, à envoyer'), findsOneWidget);
  });

  testWidgets('review buttons are hidden without the review_enrolment permission', (tester) async {
    await pumpSignedIn(tester, selected: item(), permissions: ['send_enrolment_code']);
    expect(find.text('Approuver'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
    expect(find.text('Mettre en attente'), findsNothing);
  });

  testWidgets('a server error on an action is shown in a banner', (tester) async {
    final screen = await pumpSignedIn(tester, selected: item());
    screen.adapter.reply(
        409, {'error': 'invalid_state', 'message': 'Cette demande ne peut plus être modifiée.'});
    await tester.ensureVisible(find.text('Approuver'));
    await tester.tap(find.text('Approuver'));
    await settle(tester);
    expect(find.text('Cette demande ne peut plus être modifiée.'), findsOneWidget);
  });

  testWidgets('back from the detail returns to the queue', (tester) async {
    await pumpSignedIn(tester, items: [item()], selected: item());
    await tester.tap(find.byTooltip('Retour'));
    await settle(tester);
    expect(find.text("Demandes d'enrôlement"), findsOneWidget);
  });

  for (final selected in [
    null,
    item(flags: ['device_multiple_numbers'])
  ]) {
    testWidgets(
        'small phone with large text does not overflow (${selected == null ? 'queue' : 'detail'})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSignedIn(tester,
          items: [
            item(flags: ['device_multiple_numbers'])
          ],
          selected: selected);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
