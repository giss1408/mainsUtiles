import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff/main.dart';
import 'package:staff/src/ops_controller.dart';
import 'package:staff/src/providers.dart';
import 'package:staff/src/screens/jobs_screens.dart';
import 'package:staff/src/screens/messages_screens.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

class Screen {
  final adapter = FakeAdapter();
  final opened = <Uri>[];
  bool whatsApp = true;
  late final StaffController staff;
  late final OpsController ops;
}

Future<Screen> pump(
  WidgetTester tester, {
  StaffSection section = StaffSection.messages,
  OpsState ops = const OpsState(),
  List<String> permissions = opsPermissions,
  bool small = false,
}) async {
  if (small) {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final screen = Screen();
  final api = StaffApi(dioWith(screen.adapter));
  screen.staff = StaffController(
    api: api,
    session: SignedInSession(api),
    initial: StaffState(
      stage: StaffStage.queue,
      me: StaffMe(id: 'u1', username: 'ops', permissions: permissions),
      section: section,
      items: const [],
      payments: const [],
    ),
  );
  screen.ops = OpsController(api: api, staff: screen.staff, initial: ops);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: small ? const Size(320, 640) : const Size(800, 1200),
        textScaler: TextScaler.linear(small ? 2 : 1),
      ),
      child: buildApp(overrides: [
        staffControllerProvider.overrideWith((ref) => screen.staff),
        opsControllerProvider.overrideWith((ref) => screen.ops),
        urlOpenerProvider.overrideWithValue((uri) async {
          screen.opened.add(uri);
          return screen.whatsApp;
        }),
      ]),
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

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

MessageItem message({bool urgent = false, bool late = false, bool detail = false}) =>
    MessageItem.fromJson(messageJson(urgent: urgent, late: late, detail: detail));
PayoutItem payout({bool late = false, bool detail = false, bool payable = true}) =>
    PayoutItem.fromJson(payoutJson(late: late, detail: detail, payable: payable));
DisputeItem dispute({bool late = false, bool detail = false}) =>
    DisputeItem.fromJson(disputeJson(late: late, detail: detail));

void main() {
  testWidgets('messages queue marks urgent and late, and shows no text', (tester) async {
    await pump(
      tester,
      ops: OpsState(messages: [
        message(urgent: true, late: true),
        MessageItem.fromJson(
            messageJson(id: 'm2', kind: 'paid', label: 'Jobber payé', role: 'householder')),
      ]),
    );
    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Candidature acceptée'), findsOneWidget);
    expect(find.text('Pour le jobber'), findsOneWidget);
    expect(find.text('Pour le ménage'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget);
    expect(find.textContaining('petitGombo :'), findsNothing);
  });

  testWidgets('an empty queue and a failed load say so', (tester) async {
    await pump(tester, ops: const OpsState(messages: []));
    expect(find.text('Aucun message à envoyer.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      ops: const OpsState(
          messages: [], listError: 'Pas de connexion. Vérifiez Internet et réessayez.'),
    );
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Aucun message à envoyer.'), findsNothing);
  });

  testWidgets('message detail shows the text and opens WhatsApp', (tester) async {
    final screen = await pump(
      tester,
      ops: OpsState(messages: [message()], messageSelected: message(detail: true)),
    );
    expect(find.textContaining('petitGombo : tu as été accepté(e)'), findsOneWidget);
    expect(find.text('Le message est déjà écrit. Ne le modifiez pas.'), findsOneWidget);
    expect(find.textContaining('0708091011'), findsNothing);
    screen.adapter
      ..reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=petitGombo'})
      ..reply(200, alertsJson());
    await tap(tester, find.text('Ouvrir WhatsApp'));
    expect(screen.adapter.requests.first.path, '/api/v1/staff/messages/m1/send');
    expect(screen.opened.single.host, 'wa.me');
    // Sent: back on the queue, which no longer lists it, and nothing of it is kept.
    expect(find.byType(MessagesQueueScreen), findsOneWidget);
    expect(find.text('Aucun message à envoyer.'), findsOneWidget);
    expect(screen.ops.state.messageSelected, isNull);
  });

  testWidgets('a text still loading cannot be sent', (tester) async {
    await pump(tester, ops: OpsState(messages: [message()], messageSelected: message()));
    // FilledButton.icon builds a private subclass, which byType does not match.
    final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
    expect(button.onPressed, isNull);
  });

  testWidgets('a stale message says so and cannot be sent again', (tester) async {
    final screen = await pump(
      tester,
      ops: OpsState(messages: [message()], messageSelected: message(detail: true)),
    );
    screen.adapter
      ..reply(409, {
        'error': 'message_stale',
        'message': "Ce message n'est plus d'actualité : il a été retiré.",
      })
      ..reply(200, alertsJson());
    await tap(tester, find.text('Ouvrir WhatsApp'));
    expect(find.text("Ce message n'est plus d'actualité : il a été retiré."), findsOneWidget);
    expect(screen.opened, isEmpty);
    expect(tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed, isNull);
  });

  testWidgets('a send that fails offline can be tried again', (tester) async {
    final screen = await pump(
      tester,
      ops: OpsState(messages: [message()], messageSelected: message(detail: true)),
    );
    screen.adapter.offline = true;
    await tap(tester, find.text('Ouvrir WhatsApp'));
    expect(find.text('Pas de connexion. Vérifiez Internet et réessayez.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed, isNotNull);
    screen.adapter
      ..offline = false
      ..reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=petitGombo'})
      ..reply(200, alertsJson());
    await tap(tester, find.text('Ouvrir WhatsApp'));
    expect(screen.opened.single.host, 'wa.me');
  });

  testWidgets('without WhatsApp the screen says so', (tester) async {
    final screen = await pump(
      tester,
      ops: OpsState(messages: [message()], messageSelected: message(detail: true)),
    );
    screen.whatsApp = false;
    screen.adapter
      ..reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=petitGombo'})
      ..reply(200, alertsJson());
    await tap(tester, find.text('Ouvrir WhatsApp'));
    expect(find.text("WhatsApp n'est pas installé sur cet appareil."), findsOneWidget);
  });

  testWidgets('payout tab lists amounts and recording sends the reference', (tester) async {
    final screen = await pump(
      tester,
      section: StaffSection.jobs,
      ops: OpsState(payouts: [payout(late: true)]),
    );
    expect(find.text('À verser'), findsOneWidget);
    expect(find.text('Litiges'), findsOneWidget);
    expect(find.text('3 500 FCFA'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget);
    expect(find.textContaining('07 08'), findsNothing);

    screen.adapter.reply(200, payoutJson(detail: true));
    await tap(tester, find.text('3 500 FCFA'));
    expect(find.byType(PayoutDetailScreen), findsOneWidget);
    expect(find.text('+225 07 08 09 10 11'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('payout-reference')), 'MOMO-998877');
    await settle(tester);
    screen.adapter
      ..reply(200, payoutJson())
      ..reply(200, alertsJson());
    await tap(tester, find.text('Enregistrer le versement'));
    final sent = screen.adapter.requests.firstWhere((r) => r.path.endsWith('/pay'));
    expect(sent.data, {'reference': 'MOMO-998877'});
    expect(find.byType(JobsQueueScreen), findsOneWidget);
    expect(find.text('Aucun paiement à verser.'), findsOneWidget);
    expect(screen.ops.state.payoutSelected, isNull);
  });

  testWidgets('a refunded booking shows no payout form', (tester) async {
    await pump(
      tester,
      section: StaffSection.jobs,
      ops: OpsState(payouts: [payout()], payoutSelected: payout(detail: true, payable: false)),
    );
    expect(find.text('Ne versez rien : cette réservation a été remboursée.'), findsOneWidget);
    expect(find.text('Enregistrer le versement'), findsNothing);
  });

  testWidgets('dispute detail and the three decisions', (tester) async {
    final screen = await pump(
      tester,
      section: StaffSection.jobs,
      ops: OpsState(
        jobsTab: 'disputes',
        disputes: [dispute()],
        disputeSelected: dispute(detail: true),
      ),
    );
    expect(find.text('Le salon reste sale'), findsOneWidget);
    expect(find.text('le ménage'), findsOneWidget);
    expect(find.text('Koffi · Awa'), findsOneWidget);
    expect(find.text('900 m (loin du domicile)'), findsOneWidget);
    expect(find.text('non enregistré'), findsOneWidget);
    for (final label in ['Payer le jobber', 'Rembourser le ménage', 'Partager']) {
      expect(find.text(label), findsOneWidget);
    }
    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    expect(find.byKey(const Key('dispute-share')), findsNothing);

    // A decision needs a reason.
    await tap(tester, find.text('Payer le jobber'));
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('dispute-note')), 'Moitié faite');
    await settle(tester);
    expect(button().onPressed, isNotNull);

    // A split needs an amount strictly inside the price.
    await tap(tester, find.text('Partager'));
    expect(find.byKey(const Key('dispute-share')), findsOneWidget);
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('dispute-share')), '3500');
    await settle(tester);
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('dispute-share')), '1500');
    await settle(tester);

    await tap(tester, find.text('Trancher le litige'));
    expect(find.text('Confirmer la décision ?'), findsOneWidget);
    expect(screen.adapter.requests, isEmpty);
    screen.adapter
      ..reply(200, disputeJson())
      ..reply(200, alertsJson());
    await tap(tester, find.text('Confirmer'));
    final sent = screen.adapter.requests.firstWhere((r) => r.path.endsWith('/resolve'));
    expect(sent.data, {'outcome': 'split', 'note': 'Moitié faite', 'jobber_xof': 1500});
    expect(find.byType(JobsQueueScreen), findsOneWidget);
    expect(find.text('Aucun litige ouvert.'), findsOneWidget);
  });

  testWidgets('a refused decision keeps the screen and shows the server text', (tester) async {
    final screen = await pump(
      tester,
      section: StaffSection.jobs,
      ops: OpsState(
          jobsTab: 'disputes', disputes: [dispute()], disputeSelected: dispute(detail: true)),
    );
    await tap(tester, find.text('Rembourser le ménage'));
    await tester.enterText(find.byKey(const Key('dispute-note')), 'Parti tôt');
    await settle(tester);
    await tap(tester, find.text('Trancher le litige'));
    screen.adapter.reply(
        409, {'error': 'invalid_state', 'message': 'Cette demande ne peut plus être modifiée.'});
    await tap(tester, find.text('Confirmer'));
    expect(find.text('Cette demande ne peut plus être modifiée.'), findsOneWidget);
    expect(find.byType(DisputeDetailScreen), findsOneWidget);
  });

  testWidgets('sections follow the rights and show badges', (tester) async {
    await pump(
      tester,
      permissions: ['review_enrolment', 'verify_payment', ...opsPermissions],
      ops: OpsState(
        messages: const [],
        alerts: StaffAlerts.fromJson(
          {...alertsJson(messages: 3, payouts: 1, disputes: 1), 'payments_waiting': 4},
        ),
      ),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('3'), findsOneWidget); // messages
    expect(find.text('2'), findsOneWidget); // payouts + disputes
    expect(find.text('4'), findsOneWidget); // payments
    expect(find.byTooltip('Messages : 3 en attente'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, permissions: ['send_message'], ops: const OpsState(messages: []));
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      section: StaffSection.jobs,
      permissions: ['send_message', 'resolve_dispute'],
      ops: const OpsState(jobsTab: 'disputes', disputes: []),
    );
    expect(find.text('À verser'), findsNothing);
    expect(find.text('Aucun litige ouvert.'), findsOneWidget);
  });

  testWidgets('a far check-in is announced on the jobs screen', (tester) async {
    await pump(
      tester,
      section: StaffSection.jobs,
      ops: OpsState(payouts: const [], alerts: StaffAlerts.fromJson({'far_checkins': 1})),
    );
    expect(find.textContaining('1 arrivée loin du domicile'), findsOneWidget);
  });

  testWidgets('switching section loads its queue and the counts', (tester) async {
    final screen = await pump(tester, ops: const OpsState(messages: []));
    screen.adapter
      ..reply(200, page([payoutJson()]))
      ..reply(200, alertsJson(payouts: 1));
    await tap(tester, find.byIcon(Icons.work_outline));
    expect(screen.adapter.requests.map((r) => r.path),
        ['/api/v1/staff/payouts', '/api/v1/staff/alerts']);
    expect(find.text('3 500 FCFA'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('screens fit 320dp at double text size', (tester) async {
    final all = ['review_enrolment', 'send_contact_code', 'verify_payment', ...opsPermissions];
    await pump(
      tester,
      small: true,
      permissions: all,
      ops: OpsState(
        messages: [message(urgent: true, late: true)],
        alerts: StaffAlerts.fromJson(alertsJson(messages: 12, payouts: 3)),
      ),
    );
    expect(tester.takeException(), isNull);
    final details = [
      (
        StaffSection.messages,
        OpsState(messageSelected: message(urgent: true, late: true, detail: true))
      ),
      (StaffSection.jobs, OpsState(payouts: [payout(late: true)])),
      (StaffSection.jobs, OpsState(payoutSelected: payout(late: true, detail: true))),
      (StaffSection.jobs, OpsState(payoutSelected: payout(detail: true, payable: false))),
      (StaffSection.jobs, OpsState(jobsTab: 'disputes', disputes: [dispute(late: true)])),
      (StaffSection.jobs, OpsState(disputeSelected: dispute(late: true, detail: true))),
    ];
    for (final (section, ops) in details) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, small: true, permissions: all, section: section, ops: ops);
      expect(tester.takeException(), isNull, reason: '$section');
    }
    await tap(tester, find.text('Partager'));
    expect(tester.takeException(), isNull);
  });
}
