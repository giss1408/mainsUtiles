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

JobberBooking booking(
        {String status = 'confirmed', String payment = 'confirmed', DateTime? from}) =>
    JobberBooking.fromJson({
      ...jobberBookingJson(),
      'status': status,
      'payment': payment,
      'address_available_from': (from ?? DateTime.utc(2026, 11, 14, 5)).toIso8601String(),
    });

Future<void> pump(WidgetTester tester, FakeAdapter adapter, Widget home) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        appRoleProvider.overrideWithValue(AppRole.jobber),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('my jobs words each state', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(200, {'results': []})
      ..reply(200, {
        'results': [
          {...jobberBookingJson(), 'id': 'b-1', 'payment': 'pending'},
          {...jobberBookingJson(), 'id': 'b-2', 'status': 'payment_review', 'payment': 'review'},
          {
            ...jobberBookingJson(),
            'id': 'b-3',
            'status': 'confirmed',
            'payment': 'confirmed',
            // Far ahead of the real clock, which this list reads.
            'starts_at': '2099-01-02T08:00:00Z',
            'address_available_from': '2099-01-02T05:00:00Z',
          },
          {...jobberBookingJson(), 'id': 'b-4', 'status': 'cancelled', 'payment': 'pending'},
        ]
      });
    await pump(tester, adapter, const MyApplicationsScreen());
    expect(find.text('Mes jobs'), findsOneWidget);
    expect(find.text('En attente du paiement du ménage'), findsOneWidget);
    expect(find.text('Le ménage a payé : nous vérifions'), findsOneWidget);
    expect(find.textContaining("Confirmé : l'adresse arrive"), findsOneWidget);
    expect(find.text('Annulé'), findsNothing);
  });

  testWidgets('the address is hidden until the window opens', (tester) async {
    await pump(
      tester,
      FakeAdapter()..offlineAfterReplies = true,
      JobberBookingScreen(booking: booking(), now: DateTime.utc(2026, 11, 14, 1)),
    );
    expect(find.textContaining("Confirmé : l'adresse arrive le"), findsOneWidget);
    expect(find.text("Voir l'adresse exacte"), findsNothing);
    expect(find.text('Cocody · Angré'), findsOneWidget);
    expect(find.textContaining('5.3599'), findsNothing);
  });

  testWidgets('once released the pin is shown with a copy button', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, addressJson());
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking(), now: DateTime.utc(2026, 11, 14, 6)),
    );
    expect(find.text('Adresse disponible'), findsOneWidget);
    await tap(tester, find.text("Voir l'adresse exacte"));
    expect(adapter.requests.single.path, '/api/v1/my-bookings/b-1/address');
    expect(find.text('5.35990, -3.98710'), findsOneWidget);
    expect(find.text('Copier la position'), findsOneWidget);
  });

  testWidgets('a refused address shows the server text', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(409, {
      'error': 'address_not_yet',
      'message': "L'adresse sera communiquée quelques heures avant le début.",
    });
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking(), now: DateTime.utc(2026, 11, 14, 6)),
    );
    await tap(tester, find.text("Voir l'adresse exacte"));
    expect(find.text("L'adresse sera communiquée quelques heures avant le début."), findsOneWidget);
    expect(find.text('Copier la position'), findsNothing);
  });

  testWidgets('cancel asks to confirm and says the household is refunded', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking(), now: DateTime.utc(2026, 11, 14, 1)),
    );
    await tap(tester, find.text('Annuler ma participation'));
    expect(find.text('Annuler ta participation ?'), findsOneWidget);
    expect(find.text('Le ménage sera remboursé et prévenu.'), findsOneWidget);
    adapter
      ..reply(200, {'id': 'b-1', 'status': 'cancelled'})
      ..reply(200, {'results': []})
      ..reply(200, {'results': []});
    await tap(tester, find.text('Annuler ma participation').last);
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-bookings/b-1/cancel'), isTrue);
  });

  testWidgets('a cancelled booking offers no cancel button', (tester) async {
    await pump(
      tester,
      FakeAdapter()..offlineAfterReplies = true,
      JobberBookingScreen(
          booking: booking(status: 'cancelled'), now: DateTime.utc(2026, 11, 14, 1)),
    );
    expect(find.text('Annuler ma participation'), findsNothing);
    expect(find.text('Annulé'), findsOneWidget);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, addressJson());
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
          home: JobberBookingScreen(booking: booking(), now: DateTime.utc(2026, 11, 14, 6)),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text("Voir l'adresse exacte"));
    expect(tester.takeException(), isNull);
  });
}
