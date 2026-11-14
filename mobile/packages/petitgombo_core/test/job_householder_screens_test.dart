import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';
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

Map<String, dynamic> detail(String status, [Map<String, dynamic> more = const {}]) => {
      ...bookingDetailJson(
        status: status,
        cancellable: false,
        jobber: {'full_name': 'Awa Koné', 'has_photo': false},
      ),
      ...more,
    };

const pending = {
  'checked_in_at': '2026-11-14T08:05:00Z',
  'checked_out_at': '2026-11-14T11:00:00Z',
  'auto_confirm_at': '2026-11-15T11:00:00Z',
};

Future<void> pump(WidgetTester tester, FakeAdapter adapter, Widget home,
    {bool small = false}) async {
  if (small) {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        appRoleProvider.overrideWithValue(AppRole.householder),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: small
            ? (context, child) => MediaQuery(
                  data:
                      const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
                  child: child!,
                )
            : null,
        home: home,
      ),
    ),
  );
  await settle(tester);
}

/// Throws the whole tree away, so the next pump starts from fresh providers.
Future<void> reset(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<FakeAdapter> pumpBooking(
  WidgetTester tester,
  Map<String, dynamic> body, {
  Map<String, dynamic>? review,
  bool small = false,
}) async {
  await reset(tester);
  final adapter = FakeAdapter()..offlineAfterReplies = true;
  adapter.reply(200, body);
  if (review != null) adapter.reply(200, review);
  await pump(tester, adapter, const MyBookingScreen(offerId: 'o-1'), small: small);
  return adapter;
}

void main() {
  testWidgets('states are worded', (tester) async {
    await pumpBooking(tester, detail('checked_in', {'checked_in_at': '2026-11-14T08:05:00Z'}));
    expect(find.text('Le jobber est arrivé à 08:05'), findsOneWidget);
    expect(find.text('Signaler un problème'), findsOneWidget);
    expect(find.text("Confirmer que c'est fait"), findsNothing);

    await pumpBooking(tester, detail('completion_pending', pending));
    await settle(tester);
    expect(find.textContaining('Job à confirmer avant le'), findsOneWidget);
    expect(find.textContaining('11:00'), findsOneWidget);
    expect(find.text("Confirmer que c'est fait"), findsOneWidget);
  });

  testWidgets('a completed and a disputed booking are worded', (tester) async {
    await pumpBooking(tester, detail('disputed', pending));
    expect(find.text('Problème signalé : notre équipe vous répond'), findsOneWidget);
    expect(find.text("Confirmer que c'est fait"), findsNothing);
    expect(find.text('Annuler la réservation'), findsNothing);
  });

  testWidgets('before the jobber arrives nothing can be reported', (tester) async {
    await pumpBooking(tester, detail('confirmed'));
    expect(find.text('Signaler un problème'), findsNothing);
  });

  testWidgets('confirm asks to confirm and calls the api', (tester) async {
    final adapter = await pumpBooking(tester, detail('completion_pending', pending));
    await tap(tester, find.text("Confirmer que c'est fait"));
    expect(find.text('Le job est bien fait ?'), findsOneWidget);
    expect(adapter.requests.length, 1);
    await tap(tester, find.text('Pas encore'));
    expect(adapter.requests.length, 1);

    adapter
      ..reply(200, {'id': 'b-1', 'status': 'completed'})
      ..reply(200, detail('completed', {...pending, 'auto_confirm_at': null, 'reviewable': true}))
      // The offers list reloads after a change, then the screen asks for the reviews.
      ..reply(500, <String, dynamic>{})
      ..reply(200, {'mine': null, 'theirs': null});
    await tap(tester, find.text("Confirmer que c'est fait"));
    await tap(tester, find.text('Confirmer'));
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-offers/o-1/booking/confirm'), isTrue);
    expect(find.text('Job terminé'), findsOneWidget);
    expect(find.text('Donnez votre avis'), findsWidgets);
    expect(find.text("Confirmer que c'est fait"), findsNothing);
  });

  testWidgets('report screen sends a dispute or a concern', (tester) async {
    final adapter = await pumpBooking(tester, detail('completion_pending', pending));
    await tap(tester, find.text('Signaler un problème'));
    expect(find.text("Faire geler le paiement et prévenir l'équipe"), findsOneWidget);
    expect(find.text('Remarque privée'), findsOneWidget);
    // Nothing is sent without a few words.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('report-text')), 'Rien de fait');
    await settle(tester);
    adapter
      ..reply(201, {'id': 'r-1', 'kind': 'dispute', 'booking_status': 'disputed'})
      ..reply(200, detail('disputed', pending));
    await tap(tester, find.text('Envoyer'));
    final sent = adapter.requests.firstWhere((r) => r.path.endsWith('/booking/report'));
    expect(sent.data, {'text': 'Rien de fait', 'dispute': true});
    expect(find.text('Problème signalé : notre équipe vous répond'), findsOneWidget);

    // Disputed already: only a private remark is offered.
    await tap(tester, find.text('Signaler un problème'));
    expect(find.text("Faire geler le paiement et prévenir l'équipe"), findsNothing);
    await tester.enterText(find.byKey(const Key('report-text')), 'Autre chose');
    await settle(tester);
    adapter
      ..reply(201, {'id': 'r-2', 'kind': 'concern', 'booking_status': 'disputed'})
      ..reply(200, detail('disputed', pending));
    await tap(tester, find.text('Envoyer'));
    final second = adapter.requests.lastWhere((r) => r.path.endsWith('/booking/report'));
    expect(second.data, {'text': 'Autre chose', 'dispute': false});
  });

  testWidgets('a private remark can be chosen and a refusal shows the server text', (tester) async {
    final adapter = await pumpBooking(tester, detail('checked_in'));
    await tap(tester, find.text('Signaler un problème'));
    await tap(tester, find.text('Remarque privée'));
    await tester.enterText(find.byKey(const Key('report-text')), 'Une remarque');
    await settle(tester);
    adapter.reply(400, {
      'error': 'report_invalid',
      'message': 'Le message doit faire entre 3 et 500 caractères.',
    });
    await tap(tester, find.text('Envoyer'));
    expect(adapter.requests.last.data, {'text': 'Une remarque', 'dispute': false});
    expect(find.text('Le message doit faire entre 3 et 500 caractères.'), findsOneWidget);
    expect(find.text('Envoyer'), findsOneWidget);
  });

  testWidgets('review screen validates and sends', (tester) async {
    final adapter = await pumpBooking(
      tester,
      detail('completed', {'reviewable': true}),
      review: {'mine': null, 'theirs': null},
    );
    expect(find.textContaining("Publié quand l'autre personne aura donné le sien"), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Donnez votre avis'));
    expect(find.text('Votre avis'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(const Key('review-comment'))).maxLength, 300);
    await tap(tester, find.byKey(const Key('star-4')));
    expect(find.text('4 sur 5'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('review-comment')), 'Sérieux et ponctuel');
    adapter
      ..reply(201, {
        'mine': {'stars': 4, 'comment': 'Sérieux et ponctuel'},
        'theirs': null,
      })
      ..reply(200, detail('completed'));
    await tap(tester, find.text("Envoyer l'avis"));
    final sent = adapter.requests.firstWhere((r) => r.method == 'POST');
    expect(sent.path, '/api/v1/my-offers/o-1/booking/review');
    expect(sent.data, {'stars': 4, 'comment': 'Sérieux et ponctuel'});
    expect(find.text('Avis envoyé'), findsOneWidget);
    expect(find.text('Sérieux et ponctuel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Donnez votre avis'), findsNothing);
    expect(find.text("L'avis du jobber"), findsNothing);
  });

  testWidgets('a refused review shows the server text', (tester) async {
    final adapter = await pumpBooking(
      tester,
      detail('completed', {'reviewable': true}),
      review: {'mine': null, 'theirs': null},
    );
    await tap(tester, find.widgetWithText(FilledButton, 'Donnez votre avis'));
    await tap(tester, find.byKey(const Key('star-5')));
    adapter.reply(400, {
      'error': 'message_contact_details',
      'message': 'Ne mets pas de numéro ni de contact dans ton message.',
    });
    await tap(tester, find.text("Envoyer l'avis"));
    expect(find.text('Ne mets pas de numéro ni de contact dans ton message.'), findsOneWidget);
    expect(find.text("Envoyer l'avis"), findsOneWidget);
  });

  testWidgets('the other review shows only when published', (tester) async {
    await pumpBooking(
      tester,
      detail('completed'),
      review: {
        'mine': {'stars': 4, 'comment': 'Bien'},
        'theirs': null,
      },
    );
    expect(find.text('Avis envoyé'), findsOneWidget);
    expect(find.text("L'avis du jobber"), findsNothing);

    await pumpBooking(
      tester,
      detail('completed'),
      review: {
        'mine': {'stars': 4, 'comment': 'Bien'},
        'theirs': {'stars': 5, 'comment': 'Ménage accueillant'},
      },
    );
    await settle(tester);
    expect(find.text("L'avis du jobber"), findsOneWidget);
    expect(find.text('Ménage accueillant'), findsOneWidget);
    expect(find.text('5 sur 5'), findsOneWidget);
  });

  testWidgets('a closed window with no review shows no review card', (tester) async {
    await pumpBooking(tester, detail('completed'), review: {'mine': null, 'theirs': null});
    expect(find.text('Donnez votre avis'), findsNothing);
    expect(find.text('Avis envoyé'), findsNothing);
  });

  testWidgets('applicant card shows the rating', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, {
      'payment_available': true,
      'results': [
        {...applicantJson(), 'rating': 4.5},
        applicantJson(id: 'a-2', name: 'Koffi'),
      ],
    });
    await pump(tester, adapter, const ApplicantsScreen(offerId: 'o-1'));
    expect(find.text('4,5 sur 5'), findsOneWidget);
  });

  testWidgets('screens fit 320dp at double text size', (tester) async {
    final adapter = await pumpBooking(
      tester,
      detail('completion_pending', {...pending, 'jobber_rating': 4.5}),
      small: true,
    );
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Signaler un problème'));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester);
    adapter
      ..reply(200, detail('completed', {'reviewable': true}))
      ..reply(200, {
        'mine': {'stars': 4, 'comment': 'Bien'},
        'theirs': {'stars': 5, 'comment': 'Ménage accueillant et très bien organisé'},
      });
    await reset(tester);
    await pump(tester, adapter, const MyBookingScreen(offerId: 'o-1'), small: true);
    expect(tester.takeException(), isNull);
    await reset(tester);
    await pump(tester, adapter, const ReviewScreen(target: JobTarget.householder('o-1')),
        small: true);
    await tap(tester, find.byKey(const Key('star-3')));
    expect(tester.takeException(), isNull);
  });
}
