import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';
import 'support/verification_fixtures.dart';

Map<String, dynamic> mineJson(List<Map<String, dynamic>> offers) =>
    {'can_publish': true, 'review_hours': 24, 'offers': offers};

Map<String, dynamic> catalogueJson() => {
      'categories': [categoryJson()],
      'limits': limitsJson(),
    };

Map<String, dynamic> applicantsJson(List<Map<String, dynamic>> rows) => {'results': rows};

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

Future<FakeAdapter> pumpMine(WidgetTester tester, List<Map<String, dynamic>> offers) async {
  final adapter = FakeAdapter()
    ..reply(200, mineJson(offers))
    ..reply(200, catalogueJson());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
        appRoleProvider.overrideWithValue(AppRole.householder),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: MyOffersScreen(onSignOut: () {})),
    ),
  );
  await settle(tester);
  return adapter;
}

void main() {
  testWidgets('my offers shows the applicants count on a published offer', (tester) async {
    await pumpMine(tester, [myOfferJson(status: 'published', applicantsCount: 2)]);
    expect(find.text('2 candidats'), findsOneWidget);
  });

  testWidgets('applicants are listed with first name and message', (tester) async {
    final adapter = await pumpMine(tester, [myOfferJson(status: 'published', applicantsCount: 2)]);
    await tap(tester, find.text('Ménage'));
    expect(find.text('2 candidats'), findsOneWidget);
    adapter.reply(200, applicantsJson([applicantJson(), applicantJson(id: 'a-2', name: 'Koffi')]));
    await tap(tester, find.text('2 candidats'));
    expect(adapter.requests.last.path, '/api/v1/my-offers/o-1/applicants');
    expect(find.text('Awa'), findsOneWidget);
    expect(find.text('Koffi'), findsOneWidget);
    expect(find.text('Disponible le matin.'), findsWidgets);
    expect(find.text('Accepter'), findsNWidgets(2));
  });

  testWidgets('accept asks to confirm, then shows the booked state', (tester) async {
    final adapter = await pumpMine(tester, [myOfferJson(status: 'published', applicantsCount: 1)]);
    await tap(tester, find.text('Ménage'));
    adapter.reply(200, applicantsJson([applicantJson()]));
    await tap(tester, find.text('1 candidat'));
    await tap(tester, find.text('Accepter'));
    expect(find.text('Accepter Awa ?'), findsOneWidget);
    expect(find.text('Les autres candidats seront refusés.'), findsOneWidget);
    adapter
      ..reply(201, acceptedJson())
      ..reply(200, applicantsJson([]))
      ..reply(
        200,
        mineJson([
          myOfferJson(
            status: 'booked',
            booking: {'id': 'b-1', 'status': 'accepted', 'jobber_first_name': 'Awa'},
          ),
        ]),
      )
      ..reply(200, catalogueJson());
    await tap(tester, find.text('Confirmer'));
    final accept = adapter.requests.firstWhere((r) => r.path.endsWith('/accept'));
    expect(accept.path, '/api/v1/my-offers/o-1/applicants/a-1/accept');
    expect(find.text('Réservée'), findsWidgets);
    expect(find.text('Awa · en attente de votre paiement'), findsOneWidget);
    expect(find.text('Retirer'), findsNothing);
  });

  testWidgets('a failed accept shows the server text and keeps the list', (tester) async {
    final adapter = await pumpMine(tester, [myOfferJson(status: 'published', applicantsCount: 1)]);
    await tap(tester, find.text('Ménage'));
    adapter.reply(200, applicantsJson([applicantJson()]));
    await tap(tester, find.text('1 candidat'));
    await tap(tester, find.text('Accepter'));
    adapter
      ..reply(
          409, {'error': 'applicant_not_verified', 'message': 'Ce candidat n\'est plus vérifié.'})
      ..reply(200, applicantsJson([applicantJson(id: 'a-2', name: 'Koffi')]))
      ..reply(200, mineJson([myOfferJson(status: 'published', applicantsCount: 1)]))
      ..reply(200, catalogueJson());
    await tap(tester, find.text('Confirmer'));
    expect(find.text('Ce candidat n\'est plus vérifié.'), findsOneWidget);
    expect(find.text('Koffi'), findsOneWidget);
    expect(find.text('Awa'), findsNothing);
  });

  testWidgets('a booked offer can be withdrawn, and the dialog says the booking ends',
      (tester) async {
    final adapter = await pumpMine(tester, [
      myOfferJson(
        status: 'booked',
        booking: {'id': 'b-1', 'status': 'accepted', 'jobber_first_name': 'Awa'},
      ),
    ]);
    await tap(tester, find.text('Ménage'));
    await tap(tester, find.text("Retirer l'offre"));
    expect(find.text('La réservation avec le jobber choisi sera annulée.'), findsOneWidget);
    adapter
      ..reply(200, myOfferJson(status: 'withdrawn'))
      ..reply(200, mineJson([myOfferJson(status: 'withdrawn')]))
      ..reply(200, catalogueJson());
    await tap(tester, find.text('Retirer'));
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-offers/o-1/withdraw'), isTrue);
    expect(find.text('Retirée'), findsWidgets);
  });

  testWidgets('an offer with no applicant says so', (tester) async {
    final adapter = await pumpMine(tester, [myOfferJson(status: 'published')]);
    await tap(tester, find.text('Ménage'));
    adapter.reply(200, applicantsJson([]));
    await tap(tester, find.text('Pas encore de candidat.'));
    expect(find.text('Les jobbers vérifiés qui postulent apparaissent ici.'), findsOneWidget);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter()
      ..reply(200, applicantsJson([applicantJson(name: 'Anne-Marie-Christelle')]));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          sessionProvider.overrideWithValue(SignedInSession()),
          appRoleProvider.overrideWithValue(AppRole.householder),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const ApplicantsScreen(offerId: 'o-1'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Anne-Marie-Christelle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
