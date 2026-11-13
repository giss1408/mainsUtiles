import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff/main.dart';
import 'package:staff/src/providers.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

class Screen {
  final adapter = FakeAdapter();
  late final StaffController controller;
}

Future<Screen> pump(
  WidgetTester tester, {
  List<PaymentItem> rows = const [],
  PaymentItem? selected,
  bool withProof = false,
  List<String> permissions = paymentPermissions,
  String tab = 'check',
}) async {
  final screen = Screen();
  final api = StaffApi(dioWith(screen.adapter));
  screen.controller = StaffController(
    api: api,
    session: SignedInSession(api),
    initial: StaffState(
      stage: StaffStage.queue,
      me: StaffMe(id: 'u1', username: 'cashier', permissions: permissions),
      section: StaffSection.payments,
      paymentTab: tab,
      payments: rows,
      paymentSelected: selected,
      proof: withProof ? Uint8List.fromList([0xff, 0xd8, 0xff]) : null,
      items: const [],
    ),
  );
  await tester.pumpWidget(
    buildApp(overrides: [staffControllerProvider.overrideWith((ref) => screen.controller)]),
  );
  await tester.pump();
  return screen;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

PaymentItem row(
    {bool late = false, String action = 'check', bool detail = false, bool seen = false}) {
  final json = paymentJson(late: late, action: action, detail: detail);
  if (detail) json['seen_before'] = seen;
  return PaymentItem.fromJson(json);
}

void main() {
  testWidgets('rows show amount, category, method and the late marker, never a reference',
      (tester) async {
    await pump(tester, rows: [row(late: true)]);
    expect(find.text('Paiements'), findsWidgets);
    expect(find.text('3 500 FCFA'), findsOneWidget);
    expect(find.textContaining('Ménage · Wave'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget);
    expect(find.text('WAVE-123456'), findsNothing);
  });

  testWidgets('an empty queue says so', (tester) async {
    await pump(tester);
    expect(find.text('Aucun paiement à traiter.'), findsOneWidget);
  });

  testWidgets('the refund tab is hidden without the refund right', (tester) async {
    await pump(tester, permissions: ['verify_payment']);
    expect(find.text('Remboursements'), findsNothing);
  });

  testWidgets('both tabs show to an agent with both rights', (tester) async {
    await pump(tester, permissions: paymentPermissions);
    expect(find.text('Remboursements'), findsOneWidget);
    expect(find.text('À vérifier'), findsOneWidget);
  });

  testWidgets('the detail shows the reference, the proof and the history warning', (tester) async {
    await pump(tester, rows: [row()], selected: row(detail: true), withProof: true);
    expect(find.text('WAVE-123456'), findsOneWidget);
    expect(find.textContaining('+2250101010101'), findsOneWidget);
    expect(find.textContaining('historique réel du compte'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Cette image a déjà été envoyée pour un autre paiement.'), findsNothing);
  });

  testWidgets('an image seen before is flagged', (tester) async {
    await pump(tester, rows: [row()], selected: row(detail: true, seen: true));
    expect(find.text('Cette image a déjà été envoyée pour un autre paiement.'), findsOneWidget);
  });

  testWidgets('confirm stays disabled until both checks are ticked', (tester) async {
    await pump(tester, rows: [row()], selected: row(detail: true), withProof: true);
    Finder confirm() => find.widgetWithText(FilledButton, 'Confirmer le paiement');
    expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
    await tap(tester, find.text('Le montant correspond'));
    expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
    await tap(tester, find.text('La référence correspond'));
    expect(tester.widget<FilledButton>(confirm()).onPressed, isNotNull);
  });

  testWidgets('confirm sends both checks and returns to the queue', (tester) async {
    final screen = await pump(tester, rows: [row()], selected: row(detail: true), withProof: true);
    await tap(tester, find.text('Le montant correspond'));
    await tap(tester, find.text('La référence correspond'));
    screen.adapter.reply(200, paymentJson());
    await tap(tester, find.text('Confirmer le paiement'));
    expect(screen.adapter.requests.last.path, '/api/v1/staff/payments/p1/confirm');
    expect(screen.adapter.requests.last.data, {'amount_matches': true, 'reference_matches': true});
    expect(find.text('Aucun paiement à traiter.'), findsOneWidget);
  });

  testWidgets('refuse asks for a reason', (tester) async {
    final screen = await pump(tester, rows: [row()], selected: row(detail: true), withProof: true);
    await tap(tester, find.text('Refuser le paiement'));
    await tester.enterText(find.byType(TextField), 'Montant faux');
    await tester.pump();
    screen.adapter.reply(200, paymentJson());
    await tap(tester, find.text('Confirmer'));
    expect(screen.adapter.requests.last.path, '/api/v1/staff/payments/p1/refuse');
    expect(screen.adapter.requests.last.data, {'reason': 'Montant faux'});
  });

  testWidgets('a refund asks for the transfer reference', (tester) async {
    final screen = await pump(
      tester,
      rows: [row(action: 'refund')],
      selected: row(action: 'refund', detail: true),
      tab: 'refund',
    );
    expect(find.text('Confirmer le paiement'), findsNothing);
    await tap(tester, find.text('Enregistrer le remboursement'));
    await tester.enterText(find.byType(TextField), 'RB-2001');
    await tester.pump();
    screen.adapter.reply(200, paymentJson(action: 'refund'));
    await tap(tester, find.text('Confirmer'));
    expect(screen.adapter.requests.last.path, '/api/v1/staff/payments/p1/refund');
    expect(screen.adapter.requests.last.data, {'reference': 'RB-2001'});
  });

  testWidgets('the section bar has one destination per right', (tester) async {
    await pump(tester,
        permissions: [...allPermissions, ...contactPermissions, ...paymentPermissions]);
    expect(find.text('Enrôlements'), findsOneWidget);
    expect(find.text('Personnes de confiance'), findsOneWidget);
    expect(find.text('Paiements'), findsWidgets);
  });

  testWidgets('an agent with a single right has no section bar', (tester) async {
    await pump(tester, permissions: paymentPermissions);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = StaffApi(dioWith(FakeAdapter()));
    final controller = StaffController(
      api: api,
      session: SignedInSession(api),
      initial: StaffState(
        stage: StaffStage.queue,
        me: const StaffMe(id: 'u1', username: 'c', permissions: paymentPermissions),
        section: StaffSection.payments,
        payments: [row(late: true)],
        paymentSelected: row(detail: true, seen: true),
        proof: Uint8List.fromList([0xff, 0xd8, 0xff]),
        items: const [],
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      buildApp(overrides: [staffControllerProvider.overrideWith((ref) => controller)]),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    controller.closePayment();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
