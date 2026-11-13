import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';
import 'support/verification_fixtures.dart';

Map<String, dynamic> pageJson({
  List<Map<String, dynamic>> results = const [],
  int? next,
  List<String> communes = const ['Cocody', 'Yopougon'],
}) =>
    {
      'count': results.length,
      'next': next,
      'previous': null,
      'results': results,
      'communes': communes,
    };

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<FakeAdapter> pumpOffers(WidgetTester tester, List<Object?> replies) async {
  // The verification card asks for the checklist once the offers are in; when a test queues no
  // reply for it, it fails like a lost connection and the card stays hidden.
  final adapter = FakeAdapter()..offlineAfterReplies = true;
  for (final reply in replies) {
    adapter.reply(200, reply);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        appRoleProvider.overrideWithValue(AppRole.jobber),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
        photoCaptureProvider.overrideWithValue(FakePhotoCapture()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: OffersScreen(onSignOut: () {}),
      ),
    ),
  );
  await settle(tester);
  return adapter;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

void main() {
  testWidgets('the list shows category, when, pay and place', (tester) async {
    await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()])
    ]);
    expect(find.text('Offres'), findsOneWidget);
    expect(find.text('Ménage'), findsOneWidget);
    expect(find.text('3 500 FCFA'), findsOneWidget);
    expect(find.text('Cocody · Angré'), findsOneWidget);
    expect(find.text('Toutes les communes'), findsOneWidget);
  });

  testWidgets('the empty state is shown when there are no offers', (tester) async {
    await pumpOffers(tester, [pageJson()]);
    expect(find.text('Aucune offre pour le moment.'), findsOneWidget);
  });

  testWidgets('choosing a commune reloads the list and shows its own empty state', (tester) async {
    final adapter = await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()]),
      jobberChecklistJson(), // asked for right after the first page
      pageJson(),
    ]);
    await tap(tester, find.byType(DropdownButtonFormField<String?>));
    await tap(tester, find.text('Yopougon').last);
    expect(adapter.requests.last.queryParameters, {'commune': 'Yopougon', 'page': 1});
    expect(find.text('Aucune offre dans cette commune pour le moment.'), findsOneWidget);
  });

  testWidgets('Voir plus loads the next page', (tester) async {
    final adapter = await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()], next: 2),
      jobberChecklistJson(),
      pageJson(results: [publicOfferJson(id: 'p-2')]),
    ]);
    await tap(tester, find.text('Voir plus'));
    expect(adapter.requests.last.queryParameters['page'], 2);
    expect(find.text('Ménage'), findsNWidgets(2));
    expect(find.text('Voir plus'), findsNothing);
  });

  testWidgets('a failed load shows Réessayer and recovers', (tester) async {
    final adapter = await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()])
    ]);
    adapter.offline = true;
    await tap(tester, find.byType(DropdownButtonFormField<String?>));
    await tap(tester, find.text('Yopougon').last);
    expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
    expect(find.text('Ménage'), findsOneWidget); // the list stays
    adapter
      ..offline = false
      ..reply(200, pageJson(results: [publicOfferJson(id: 'p-9')]));
    await tap(tester, find.text('Réessayer'));
    expect(find.text('Pas de connexion. Réessayez.'), findsNothing);
  });

  testWidgets('the detail shows the duties, the place and the address notice, and a way to apply',
      (tester) async {
    await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()])
    ]);
    await tap(tester, find.text('Ménage'));
    expect(find.text('Tâches'), findsOneWidget);
    expect(find.text('• Dépoussiérer'), findsOneWidget);
    expect(find.text('Cocody · Angré'), findsOneWidget);
    expect(find.text("L'adresse exacte est communiquée seulement après une réservation confirmée."),
        findsOneWidget);
    expect(find.text('Postuler'), findsOneWidget);
    expect(find.textContaining('+225'), findsNothing);
  });

  testWidgets('the list does not overflow on a 320dp phone at twice the text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter()
      ..reply(200, pageJson(results: [publicOfferJson()]))
      ..reply(200, jobberChecklistJson()); // the card is on screen too
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          sessionProvider.overrideWithValue(SignedInSession()),
          appRoleProvider.overrideWithValue(AppRole.jobber),
          positionReaderProvider.overrideWithValue(FakePositionReader()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
          child: MaterialApp(theme: buildAppTheme(), home: OffersScreen(onSignOut: () {})),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Fais vérifier ton compte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers screen shows the verification card with progress', (tester) async {
    await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()]),
      jobberChecklistJson(identity: {'status': 'confirmed', 'reason': ''}),
    ]);
    expect(find.text('Fais vérifier ton compte'), findsOneWidget);
    expect(find.text('1 étape sur 4'), findsOneWidget);
    expect(find.text('Compte vérifié'), findsNothing);
  });

  testWidgets('the card progress counts the steps the server requires', (tester) async {
    final json = jobberChecklistJson(
      identity: {'status': 'confirmed', 'reason': ''},
      contact: contactStepJson(status: 'confirmed', confirmed: 1),
    );
    await pumpOffers(tester, [pageJson(), json]);
    expect(find.text('2 étapes sur 4'), findsOneWidget);
  });

  testWidgets('with only two required steps the card says sur 2', (tester) async {
    final json = jobberChecklistJson(identity: {'status': 'confirmed', 'reason': ''})
      ..['required'] = ['identity', 'guarantor'];
    await pumpOffers(tester, [pageJson(), json]);
    expect(find.text('1 étape sur 2'), findsOneWidget);
  });

  testWidgets('at J1 the card says the account is verified', (tester) async {
    await pumpOffers(tester, [
      pageJson(),
      jobberChecklistJson(
        tier: 'J1',
        identity: {'status': 'confirmed', 'reason': ''},
        guarantor: {'status': 'confirmed', 'reason': ''},
      ),
    ]);
    expect(find.text('Compte vérifié'), findsOneWidget);
    expect(find.text('Fais vérifier ton compte'), findsNothing);
  });

  testWidgets('the card opens the checklist', (tester) async {
    await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()]),
      jobberChecklistJson(),
      jobberChecklistJson(),
    ]);
    await tap(tester, find.text('Fais vérifier ton compte'));
    expect(find.text('Vérifie ton compte'), findsOneWidget);
    expect(find.text('Garant'), findsOneWidget);
  });

  testWidgets('a failed checklist load hides the card and offers still show', (tester) async {
    await pumpOffers(tester, [
      pageJson(results: [publicOfferJson()]),
    ]);
    expect(find.text('Fais vérifier ton compte'), findsNothing);
    expect(find.text('Compte vérifié'), findsNothing);
    expect(find.text('Ménage'), findsOneWidget);
  });
}
