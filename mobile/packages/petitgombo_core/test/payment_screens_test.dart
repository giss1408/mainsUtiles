import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';
import 'support/verification_fixtures.dart';

class FakePicker implements ProofPicker {
  int calls = 0;
  bool unreadable = false;

  @override
  Future<CapturedPhoto?> pick() async {
    calls++;
    if (unreadable) throw const FormatException('not an image');
    return CapturedPhoto(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]),
      capturedAt: DateTime.utc(2026, 11, 13, 10),
    );
  }
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

Future<FakePicker> pump(WidgetTester tester, FakeAdapter adapter, Widget home) async {
  final picker = FakePicker();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        appRoleProvider.overrideWithValue(AppRole.householder),
        proofPickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ),
  );
  await settle(tester);
  return picker;
}

Future<FakeAdapter> pumpBooking(WidgetTester tester, Map<String, dynamic> detail) async {
  final adapter = FakeAdapter()..offlineAfterReplies = true;
  adapter.reply(200, detail);
  await pump(tester, adapter, const MyBookingScreen(offerId: 'o-1'));
  return adapter;
}

void main() {
  testWidgets('the booking screen words each state', (tester) async {
    await pumpBooking(tester, bookingDetailJson());
    expect(find.textContaining('Paiement à envoyer avant'), findsOneWidget);
    expect(find.text('Awa'), findsOneWidget);
    expect(find.text('3 500 FCFA'), findsOneWidget);
    expect(find.text('Payer'), findsOneWidget);
    expect(find.text('Annuler la réservation'), findsOneWidget);
  });

  testWidgets('a proof under review has no pay button', (tester) async {
    await pumpBooking(
      tester,
      bookingDetailJson(status: 'payment_review', payment: {'status': 'submitted', 'reason': ''}),
    );
    expect(find.text('Paiement en cours de vérification'), findsOneWidget);
    expect(find.text('Payer'), findsNothing);
  });

  testWidgets('a refused payment shows the reason and offers a new proof', (tester) async {
    await pumpBooking(
      tester,
      bookingDetailJson(payment: {'status': 'refused', 'reason': 'Montant faux'}),
    );
    expect(find.text('Paiement refusé : Montant faux'), findsOneWidget);
    expect(find.text('Envoyer une nouvelle preuve'), findsOneWidget);
  });

  testWidgets('a confirmed booking shows the full name and loads the photo', (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter
      ..reply(
        200,
        bookingDetailJson(
          status: 'confirmed',
          jobber: {'full_name': 'Awa Koné', 'has_photo': true},
          payment: {'status': 'confirmed', 'reason': ''},
        ),
      )
      ..replyBytes(200, [0xff, 0xd8, 0xff]);
    await pump(tester, adapter, const MyBookingScreen(offerId: 'o-1'));
    expect(find.text('Réservation confirmée'), findsOneWidget);
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(adapter.requests.last.path, '/api/v1/my-offers/o-1/booking/photo');
    expect(find.text('Payer'), findsNothing);
  });

  testWidgets('cancel asks to confirm then sends the reason', (tester) async {
    final adapter = await pumpBooking(tester, bookingDetailJson());
    await tap(tester, find.text('Annuler la réservation'));
    expect(find.text('Annuler la réservation ?'), findsOneWidget);
    adapter
      ..reply(200, {'id': 'b-1', 'status': 'cancelled'})
      ..reply(404, {'error': 'not_found', 'message': 'Réservation introuvable.'});
    await tap(tester, find.text('Annuler la réservation').last);
    expect(adapter.requests.any((r) => r.path == '/api/v1/my-offers/o-1/booking/cancel'), isTrue);
  });

  testWidgets('the payment screen shows the methods and sends the proof', (tester) async {
    final adapter = await pumpBooking(tester, bookingDetailJson());
    await tap(tester, find.text('Payer'));
    expect(find.text('Payer la réservation'), findsOneWidget);
    expect(find.text('Wave'), findsOneWidget);
    expect(find.text('MTN MoMo'), findsOneWidget);
    expect(find.text('+2250101010101'), findsWidgets);
    final send = find.text('Envoyer la preuve');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Envoyer la preuve'))
            .onPressed,
        isNull);
    await tap(tester, find.text('Wave'));
    await tester.enterText(find.byKey(const Key('payment-reference')), 'WAVE-123456');
    await tap(tester, find.text("Choisir la capture d'écran"));
    expect(find.text('Changer la capture'), findsOneWidget);
    adapter
      ..reply(201, {'id': 'p-1', 'status': 'submitted'})
      ..reply(
        200,
        bookingDetailJson(status: 'payment_review', payment: {'status': 'submitted', 'reason': ''}),
      )
      ..reply(200, {'can_publish': true, 'review_hours': 24, 'offers': []})
      ..reply(200, {
        'categories': [categoryJson()],
        'limits': limitsJson()
      });
    await tap(tester, send);
    final upload = adapter.requests.firstWhere((r) => r.path.endsWith('/booking/payment'));
    final fields = {for (final f in (upload.data as FormData).fields) f.key: f.value};
    expect(fields['method_id'], '1');
    expect(fields['reference'], 'WAVE-123456');
    expect(find.text('Paiement en cours de vérification'), findsOneWidget);
  });

  testWidgets('a refused proof keeps the reference and shows the server text', (tester) async {
    final adapter = await pumpBooking(tester, bookingDetailJson());
    await tap(tester, find.text('Payer'));
    await tap(tester, find.text('Wave'));
    await tester.enterText(find.byKey(const Key('payment-reference')), 'WAVE-123456');
    await tap(tester, find.text("Choisir la capture d'écran"));
    adapter.reply(
        409, {'error': 'payment_window_closed', 'message': 'Le délai pour payer est dépassé.'});
    await tap(tester, find.text('Envoyer la preuve'));
    expect(find.text('Le délai pour payer est dépassé.'), findsOneWidget);
    expect(find.text('WAVE-123456'), findsOneWidget);
    expect(find.text('Payer la réservation'), findsOneWidget);
  });

  testWidgets('an unreadable image shows a message and keeps the screen', (tester) async {
    final adapter = await pumpBooking(tester, bookingDetailJson());
    await tap(tester, find.text('Payer'));
    final container = ProviderScope.containerOf(tester.element(find.text('Payer la réservation')));
    (container.read(proofPickerProvider) as FakePicker).unreadable = true;
    await tap(tester, find.text("Choisir la capture d'écran"));
    expect(find.text('Cette image ne peut pas être lue. Choisissez une autre capture.'),
        findsOneWidget);
    expect(find.text("Choisir la capture d'écran"), findsOneWidget);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('without a payment method the accept buttons are replaced by the notice',
      (tester) async {
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(200, {
      'results': [applicantJson()],
      'payment_available': false,
    });
    await pump(tester, adapter, const ApplicantsScreen(offerId: 'o-1'));
    expect(find.text("Le paiement n'est pas disponible pour le moment."), findsOneWidget);
    expect(find.text('Accepter'), findsNothing);
    expect(find.text('Awa'), findsOneWidget);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter()..offlineAfterReplies = true;
    adapter.reply(
        200,
        bookingDetailJson(
            payment: {'status': 'refused', 'reason': 'Le montant reçu ne correspond pas'}));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(adapter)),
          sessionProvider.overrideWithValue(SignedInSession()),
          appRoleProvider.overrideWithValue(AppRole.householder),
          proofPickerProvider.overrideWithValue(FakePicker()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const MyBookingScreen(offerId: 'o-1'),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Envoyer une nouvelle preuve'));
    expect(tester.takeException(), isNull);
  });
}
