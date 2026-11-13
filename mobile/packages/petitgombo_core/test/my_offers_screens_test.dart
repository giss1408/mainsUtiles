import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';
import 'support/verification_fixtures.dart';

Map<String, dynamic> mineJson(
        {List<Map<String, dynamic>> offers = const [], bool canPublish = true}) =>
    {
      'can_publish': canPublish,
      'review_hours': 24,
      'offers': offers,
    };

Map<String, dynamic> catalogueJson() => {
      'categories': [categoryJson()],
      'limits': limitsJson(),
    };

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<FakeAdapter> pumpMine(
  WidgetTester tester, {
  List<Map<String, dynamic>> offers = const [],
  bool canPublish = true,
}) async {
  final adapter = FakeAdapter()
    ..reply(200, mineJson(offers: offers, canPublish: canPublish))
    ..reply(200, catalogueJson());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
        appRoleProvider.overrideWithValue(AppRole.householder),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MyOffersScreen(onSignOut: () {}),
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

Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text));

Future<void> continueStep(WidgetTester tester) => tapText(tester, 'Continuer');

void main() {
  testWidgets('empty state and Créer une offre are shown when there are no offers', (tester) async {
    await pumpMine(tester);
    expect(find.text('Mes offres'), findsOneWidget);
    expect(find.text("Vous n'avez pas encore d'offre."), findsOneWidget);
    expect(find.text('Créer une offre'), findsOneWidget);
  });

  testWidgets('without verification there is no Créer une offre but a reminder', (tester) async {
    await pumpMine(tester, canPublish: false);
    expect(find.text('Créer une offre'), findsNothing);
    expect(find.text('Faites vérifier votre compte pour publier une offre.'), findsOneWidget);
  });

  testWidgets('each status shows its French label', (tester) async {
    await pumpMine(tester, offers: [
      for (final status in ['draft', 'in_review', 'published', 'refused', 'withdrawn', 'closed'])
        myOfferJson(id: 'o-$status', status: status),
    ]);
    expect(find.text('Brouillon'), findsOneWidget);
    expect(find.text('En cours de vérification'), findsOneWidget);
    expect(find.text('Publiée'), findsOneWidget);
    expect(find.text('Refusée'), findsOneWidget);
    expect(find.text('Retirée'), findsOneWidget);
    expect(find.text('Terminée'), findsOneWidget);
  });

  testWidgets('the whole creation flow sends the draft, then publishes it as a first offer',
      (tester) async {
    final adapter = await pumpMine(tester);
    adapter
      ..reply(201, myOfferJson(id: 'new'))
      ..reply(200, myOfferJson(id: 'new'))
      ..reply(200, myOfferJson(id: 'new', status: 'in_review'));

    await tapText(tester, 'Créer une offre');
    await tapText(tester, 'Ménage');

    await tapText(tester, 'Dépoussiérer');
    await continueStep(tester);

    await tap(tester, find.byKey(const Key('offer-date')));
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tap(tester, find.text('${tomorrow.day}'));
    await tapText(tester, 'OK');
    await tap(tester, find.byKey(const Key('offer-time')));
    await tapText(tester, 'OK');
    await tapText(tester, '3 h');
    await continueStep(tester);

    await tester.enterText(find.byKey(const Key('offer-pay')), '3500');
    await settle(tester);
    await continueStep(tester);
    await continueStep(tester);

    await tapText(tester, "Publier l'offre");

    final create =
        adapter.requests.firstWhere((r) => r.method == 'POST' && r.path == '/api/v1/my-offers');
    expect(create.data['category_id'], 1);
    expect(create.data['duties'], ['Dépoussiérer']);
    expect(create.data['duration_minutes'], 180);
    expect(create.data['pay_xof'], 3500);
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-offers/new/send'), isTrue);
    expect(find.text('Offre envoyée. Nous la vérifions sous 24 h.'), findsOneWidget);
  });

  testWidgets('Continuer stays disabled until a duty is ticked', (tester) async {
    await pumpMine(tester);
    await tapText(tester, 'Créer une offre');
    await tapText(tester, 'Ménage');
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'));
    expect(button.onPressed, isNull);
    await tapText(tester, 'Dépoussiérer');
    final enabled = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'));
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('a pay outside the limits shows the message and blocks Continuer', (tester) async {
    await pumpMine(tester);
    await tapText(tester, 'Créer une offre');
    await tapText(tester, 'Ménage');
    await tapText(tester, 'Dépoussiérer');
    await continueStep(tester);
    await tap(tester, find.byKey(const Key('offer-date')));
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tap(tester, find.text('${tomorrow.day}'));
    await tapText(tester, 'OK');
    await tap(tester, find.byKey(const Key('offer-time')));
    await tapText(tester, 'OK');
    await tapText(tester, '3 h');
    await continueStep(tester);

    await tester.enterText(find.byKey(const Key('offer-pay')), '999');
    await settle(tester);
    expect(find.text('Indiquez un montant entre 1 000 et 100 000 FCFA.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'));
    expect(button.onPressed, isNull);
  });

  testWidgets('a refused offer shows its reason and Créer une offre semblable', (tester) async {
    await pumpMine(tester, offers: [
      myOfferJson(id: 'o-r', status: 'refused', reason: 'Photo illisible.'),
    ]);
    await tapText(tester, 'Refusée');
    expect(find.text('Photo illisible.'), findsOneWidget);
    expect(find.text('Créer une offre semblable'), findsOneWidget);
  });

  testWidgets("Retirer l'offre asks for confirmation then withdraws", (tester) async {
    final adapter = await pumpMine(tester, offers: [myOfferJson(id: 'o-1', status: 'published')]);
    adapter.reply(200, myOfferJson(id: 'o-1', status: 'withdrawn'));
    await tapText(tester, 'Publiée');
    await tapText(tester, "Retirer l'offre");
    expect(find.text('Retirer cette offre ?'), findsOneWidget);
    await tap(
        tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Retirer')));
    expect(adapter.requests.last.path, '/api/v1/my-offers/o-1/withdraw');
    expect(find.text('Retirée'), findsOneWidget);
  });

  testWidgets('Supprimer removes a draft and returns to the list', (tester) async {
    final adapter = await pumpMine(tester, offers: [myOfferJson(id: 'o-1', status: 'draft')]);
    adapter.reply(204, null);
    await tapText(tester, 'Brouillon');
    await tapText(tester, 'Supprimer');
    expect(find.text('Supprimer ce brouillon ?'), findsOneWidget);
    await tap(
        tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
    expect(adapter.requests.any((r) => r.method == 'DELETE' && r.path == '/api/v1/my-offers/o-1'),
        isTrue);
    expect(find.text("Vous n'avez pas encore d'offre."), findsOneWidget);
  });

  testWidgets('the list does not overflow on a 320dp phone at twice the text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(
            FakeAdapter()
              ..reply(200, mineJson(offers: [myOfferJson(status: 'published')]))
              ..reply(200, catalogueJson()),
          )),
          sessionProvider.overrideWithValue(SignedInSession()),
          positionReaderProvider.overrideWithValue(FakePositionReader()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
          child: MaterialApp(theme: buildAppTheme(), home: MyOffersScreen(onSignOut: () {})),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
