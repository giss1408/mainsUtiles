import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';
import 'support/verification_fixtures.dart';

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

Future<void> pump(WidgetTester tester, FakeAdapter adapter, Widget home) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        appRoleProvider.overrideWithValue(AppRole.jobber),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
        photoCaptureProvider.overrideWithValue(FakePhotoCapture()),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ),
  );
  await settle(tester);
}

/// The offer detail, with the replies it asks for: the offer, then the checklist.
Future<FakeAdapter> pumpDetail(
  WidgetTester tester, {
  String tier = 'J1',
  Map<String, dynamic>? application,
}) async {
  final adapter = FakeAdapter()..offlineAfterReplies = true;
  adapter
    ..reply(200, {
      ...publicOfferJson(),
      'householder': trustJson(),
      'my_application': application,
    })
    ..reply(200, jobberChecklistJson(tier: tier));
  await pump(tester, adapter, OfferDetailScreen(offer: PublicOffer.fromJson(publicOfferJson())));
  return adapter;
}

void main() {
  testWidgets('a J1 jobber sees the trust line and the apply button', (tester) async {
    await pumpDetail(tester);
    expect(find.text('Ménage vérifié · 3 jobs terminés'), findsOneWidget);
    expect(find.text('Postuler'), findsOneWidget);
    expect(find.text('Termine ta vérification pour postuler'), findsNothing);
  });

  testWidgets('a jobber who is not J1 is sent to the checklist instead', (tester) async {
    await pumpDetail(tester, tier: 'J0');
    expect(find.text('Postuler'), findsNothing);
    expect(find.text('Termine ta vérification pour postuler'), findsOneWidget);
  });

  testWidgets('apply sends the message and the detail shows the sent state', (tester) async {
    final adapter = await pumpDetail(tester);
    await tap(tester, find.text('Postuler'));
    expect(find.text('Postuler à cette offre'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('apply-message')), 'Je suis disponible.');
    adapter.reply(201, {
      'id': 'a-1',
      'offer_id': 'p-1',
      'status': 'pending',
      'created_at': '2026-11-12T10:00:00Z',
    });
    await tap(tester, find.text('Envoyer ma candidature'));
    final request = adapter.requests.last;
    expect(request.path, '/api/v1/offers/p-1/apply');
    expect(request.data, {'message': 'Je suis disponible.'});
    expect(find.text('Candidature envoyée'), findsOneWidget);
    expect(find.text('Retirer ma candidature'), findsOneWidget);
    expect(find.text('Postuler'), findsNothing);
  });

  testWidgets('a refused message stays in the field with the server text', (tester) async {
    final adapter = await pumpDetail(tester);
    await tap(tester, find.text('Postuler'));
    await tester.enterText(find.byKey(const Key('apply-message')), '07 08 09 10 11');
    adapter.reply(400, {
      'error': 'message_contact_details',
      'message': 'Ne mets pas de numéro ni de contact dans ton message.',
    });
    await tap(tester, find.text('Envoyer ma candidature'));
    expect(find.text('Ne mets pas de numéro ni de contact dans ton message.'), findsOneWidget);
    expect(find.text('07 08 09 10 11'), findsOneWidget);
    expect(find.text('Postuler à cette offre'), findsOneWidget);
  });

  testWidgets('withdrawing from the detail brings the apply button back', (tester) async {
    final adapter = await pumpDetail(tester, application: {'id': 'a-1', 'status': 'pending'});
    expect(find.text('Candidature envoyée'), findsOneWidget);
    adapter.reply(200, {
      'id': 'a-1',
      'offer_id': 'p-1',
      'status': 'withdrawn',
      'created_at': '2026-11-12T10:00:00Z',
    });
    await tap(tester, find.text('Retirer ma candidature'));
    expect(adapter.requests.last.path, '/api/v1/my-applications/a-1/withdraw');
    expect(find.text('Postuler'), findsOneWidget);
  });

  testWidgets('my applications lists, withdraws and explains an accepted one', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(200, {
        'results': [
          applicationItemJson(),
          applicationItemJson(
            id: 'a-2',
            status: 'accepted',
            booking: {'id': 'b-1', 'status': 'accepted'},
          ),
        ]
      })
      ..reply(200, {
        'results': [jobberBookingJson()]
      });
    await pump(tester, adapter, const MyApplicationsScreen());
    expect(find.text('Mes candidatures'), findsOneWidget);
    expect(find.text('En attente de réponse'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    expect(find.text('Acceptée : le ménage doit encore payer.'), findsOneWidget);
    adapter.reply(200, {
      'id': 'a-1',
      'offer_id': 'o-1',
      'status': 'withdrawn',
      'created_at': '2026-11-12T10:00:00Z',
    });
    await tap(tester, find.text('Retirer ma candidature'));
    expect(find.text('Retirée'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(200, {'results': []})
      ..reply(200, {'results': []});
    await pump(tester, adapter, const MyApplicationsScreen());
    expect(find.text("Tu n'as pas encore postulé."), findsOneWidget);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(200, {
        ...publicOfferJson(),
        'householder': trustJson(jobsDone: 12),
        'my_application': null,
      })
      ..reply(200, jobberChecklistJson(tier: 'J1'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          sessionProvider.overrideWithValue(SignedInSession()),
          appRoleProvider.overrideWithValue(AppRole.jobber),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: OfferDetailScreen(offer: PublicOffer.fromJson(publicOfferJson())),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Postuler'));
    expect(tester.takeException(), isNull);
  });
}
