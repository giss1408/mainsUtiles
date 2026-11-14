import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

class FakePosition implements PositionReader {
  FakePosition({this.failure});

  final CaptureFailure? failure;
  int reads = 0;

  @override
  Future<DevicePosition> current() async {
    reads++;
    if (failure != null) throw CaptureException(failure!);
    return DevicePosition(
      lat: 5.36,
      lng: -3.98,
      accuracyM: 12,
      mocked: false,
      capturedAt: DateTime.utc(2026, 11, 14, 8),
    );
  }

  @override
  Future<void> openSettings() async {}
}

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

Map<String, dynamic> job(String status, [Map<String, dynamic> more = const {}]) => {
      ...jobberBookingJson(),
      'status': status,
      'payment': 'confirmed',
      ...more,
    };

JobberBooking booking(String status, [Map<String, dynamic> more = const {}]) =>
    JobberBooking.fromJson(job(status, more));

final beforeStart = DateTime.utc(2026, 11, 14, 7, 45);

Future<void> pump(
  WidgetTester tester,
  FakeAdapter adapter,
  Widget home, {
  PositionReader? position,
  bool small = false,
}) async {
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
        appRoleProvider.overrideWithValue(AppRole.jobber),
        if (position != null) positionReaderProvider.overrideWithValue(position),
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

void reloadsWith(FakeAdapter adapter, Map<String, dynamic> row) => adapter
  ..reply(200, {'results': []})
  ..reply(200, {
    'results': [row]
  });

void main() {
  testWidgets('check in button appears in time and sends the position', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    final position = FakePosition();
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking('confirmed'), now: DateTime.utc(2026, 11, 14, 7)),
      position: position,
    );
    expect(find.text('Je suis arrivé(e)'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking('address_released'), now: beforeStart),
      position: position,
    );
    expect(find.text('Je suis arrivé(e)'), findsOneWidget);
    // One primary action: the address button steps back.
    expect(find.widgetWithText(OutlinedButton, "Voir l'adresse exacte"), findsOneWidget);
    adapter.reply(200, {'id': 'b-1', 'status': 'checked_in'});
    reloadsWith(adapter, job('checked_in', {'checked_in_at': '2026-11-14T07:46:00Z'}));
    await tap(tester, find.text('Je suis arrivé(e)'));
    final sent = adapter.requests.firstWhere((r) => r.path.endsWith('/check-in'));
    expect(sent.data, {'lat': 5.36, 'lng': -3.98, 'accuracy_m': 12.0});
    expect(position.reads, 1);
    expect(find.text('Je suis arrivé(e)'), findsNothing);
    expect(find.text("J'ai terminé"), findsOneWidget);
    expect(find.text('Job en cours'), findsOneWidget);
    expect(find.textContaining('sans ta position'), findsNothing);
    expect(find.text('Annuler ma participation'), findsNothing);
  });

  testWidgets('the button is gone once the job is over', (tester) async {
    await pump(
      tester,
      FakeAdapter()..offlineAfterReplies = true,
      JobberBookingScreen(booking: booking('confirmed'), now: DateTime.utc(2026, 11, 14, 11, 1)),
    );
    expect(find.text('Je suis arrivé(e)'), findsNothing);
  });

  testWidgets('check in without a position says so and still works', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking('confirmed'), now: beforeStart),
      position: FakePosition(failure: CaptureFailure.permissionDenied),
    );
    adapter.reply(200, {'id': 'b-1', 'status': 'checked_in'});
    reloadsWith(adapter, job('checked_in'));
    await tap(tester, find.text('Je suis arrivé(e)'));
    final sent = adapter.requests.firstWhere((r) => r.path.endsWith('/check-in'));
    expect(sent.data, <String, dynamic>{});
    expect(find.textContaining('sans ta position'), findsOneWidget);
    expect(find.text("J'ai terminé"), findsOneWidget);
  });

  testWidgets('a refused check in shows the server text', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    await pump(
        tester, adapter, JobberBookingScreen(booking: booking('confirmed'), now: beforeStart));
    adapter.reply(409, {
      'error': 'checkin_too_early',
      'message': 'Tu pourras confirmer ton arrivée peu avant le début.',
    });
    await tap(tester, find.text('Je suis arrivé(e)'));
    expect(find.text('Tu pourras confirmer ton arrivée peu avant le début.'), findsOneWidget);
    expect(find.text('Je suis arrivé(e)'), findsOneWidget);
  });

  testWidgets('check out and the wait are worded', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    await pump(tester, adapter, JobberBookingScreen(booking: booking('checked_in')));
    await tap(tester, find.text("J'ai terminé"));
    expect(find.text('Tu as terminé le job ?'), findsOneWidget);
    adapter.reply(200, {'id': 'b-1', 'status': 'completion_pending'});
    reloadsWith(
      adapter,
      job('completion_pending', {
        'checked_out_at': '2026-11-14T11:00:00Z',
        'auto_confirm_at': '2026-11-15T11:00:00Z',
      }),
    );
    await tap(tester, find.widgetWithText(TextButton, "J'ai terminé"));
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-bookings/b-1/check-out'), isTrue);
    expect(find.textContaining("Le ménage a jusqu'au"), findsOneWidget);
    expect(find.textContaining('pour confirmer'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, "J'ai terminé"), findsNothing);
    expect(find.text('Signaler un problème'), findsOneWidget);
  });

  testWidgets('payout states are worded', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, {'mine': null, 'theirs': null});
    await pump(
        tester, adapter, JobberBookingScreen(booking: booking('completed', {'payout': 'due'})));
    expect(find.text('Paiement en préparation'), findsOneWidget);
    expect(find.text('Terminé · paiement en préparation'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    adapter.reply(200, {'mine': null, 'theirs': null});
    await pump(
        tester, adapter, JobberBookingScreen(booking: booking('completed', {'payout': 'paid'})));
    expect(find.text('Paiement envoyé'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, adapter, JobberBookingScreen(booking: booking('disputed')));
    expect(find.text('Problème signalé : notre équipe regarde'), findsOneWidget);
    expect(find.text('Paiement en préparation'), findsNothing);
  });

  testWidgets('my jobs words the new states', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(200, {'results': []})
      ..reply(200, {
        'results': [
          {...job('checked_in'), 'id': 'b-1'},
          {...job('completion_pending'), 'id': 'b-2'},
          {
            ...job('completed', {'payout': 'paid'}),
            'id': 'b-3'
          },
          {...job('disputed'), 'id': 'b-4'},
        ]
      });
    await pump(tester, adapter, const MyApplicationsScreen());
    expect(find.text('Job en cours'), findsOneWidget);
    expect(find.text('En attente de la confirmation du ménage'), findsOneWidget);
    expect(find.text('Terminé · paiement envoyé'), findsOneWidget);
    expect(find.text('Problème signalé : notre équipe regarde'), findsOneWidget);
  });

  testWidgets('report and review reuse the shared screens', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, {'mine': null, 'theirs': null});
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking('completed', {'payout': 'due', 'reviewable': true})),
    );
    expect(adapter.requests.single.path, '/api/v1/my-bookings/b-1/review');
    await tap(tester, find.widgetWithText(FilledButton, 'Donne ton avis'));
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Ton avis'), findsOneWidget);
    await tap(tester, find.byKey(const Key('star-5')));
    adapter.reply(201, {
      'mine': {'stars': 5, 'comment': ''},
      'theirs': {'stars': 4, 'comment': 'Travail soigné'},
    });
    reloadsWith(adapter, job('completed', {'payout': 'due'}));
    await tap(tester, find.text("Envoyer l'avis"));
    final sent = adapter.requests.firstWhere((r) => r.method == 'POST');
    expect(sent.path, '/api/v1/my-bookings/b-1/review');
    expect(sent.data, {'stars': 5, 'comment': ''});
    expect(find.text('Avis envoyé'), findsOneWidget);
    expect(find.text("L'avis du ménage"), findsOneWidget);
    expect(find.text('Travail soigné'), findsOneWidget);

    await tap(tester, find.text('Signaler un problème'));
    expect(find.byType(ReportScreen), findsOneWidget);
    // Completed: only a private remark is left.
    expect(find.text("Faire geler le paiement et prévenir l'équipe"), findsNothing);
    await tester.enterText(find.byKey(const Key('report-text')), 'Le chien mord');
    await settle(tester);
    adapter.reply(201, {'id': 'r-1', 'kind': 'concern', 'booking_status': 'completed'});
    reloadsWith(adapter, job('completed', {'payout': 'due'}));
    await tap(tester, find.text('Envoyer'));
    final report = adapter.requests.firstWhere((r) => r.path.endsWith('/report'));
    expect(report.path, '/api/v1/my-bookings/b-1/report');
    expect(report.data, {'text': 'Le chien mord', 'dispute': false});
  });

  testWidgets('screens fit 320dp at double text size', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    await pump(
      tester,
      adapter,
      JobberBookingScreen(booking: booking('address_released'), now: beforeStart),
      small: true,
    );
    expect(tester.takeException(), isNull);
    for (final row in [
      booking('checked_in'),
      booking('completion_pending', {'auto_confirm_at': '2026-11-15T11:00:00Z'}),
      booking('completed', {'payout': 'due', 'reviewable': true}),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, adapter, JobberBookingScreen(booking: row), small: true);
      expect(tester.takeException(), isNull);
    }
    await tap(tester, find.text('Signaler un problème'));
    expect(tester.takeException(), isNull);
  });
}
