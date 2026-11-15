// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:staff/src/ops_controller.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_copy.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

class Ops {
  final adapter = FakeAdapter();
  late final StaffController staff;
  late final OpsController ops;
}

Ops harness({List<String> permissions = opsPermissions}) {
  final h = Ops();
  final api = StaffApi(dioWith(h.adapter));
  h.staff = StaffController(
    api: api,
    session: SignedInSession(api),
    initial: StaffState(
      stage: StaffStage.queue,
      me: StaffMe(id: 'u1', username: 'ops', permissions: permissions),
      section: StaffSection.messages,
    ),
  );
  h.ops = OpsController(api: api, staff: h.staff);
  return h;
}

void main() {
  test('entering messages loads the queue and the counts', () async {
    final h = harness();
    h.adapter
      ..reply(200, page([messageJson(urgent: true)]))
      ..reply(200, alertsJson(messages: 1));
    await h.ops.enter(StaffSection.messages);
    expect(
        h.adapter.requests.map((r) => r.path), ['/api/v1/staff/messages', '/api/v1/staff/alerts']);
    expect(h.ops.state.messages!.single.urgent, isTrue);
    expect(h.ops.state.messages!.single.text, isNull);
    expect(h.ops.state.alerts!.messages, 1);
  });

  test('alerts keep only the counts the server sent', () {
    final alerts = StaffAlerts.fromJson({'messages_waiting': 2, 'messages_late': 1});
    expect(alerts.messages, 2);
    expect(alerts.messagesLate, isTrue);
    expect(alerts['payouts_waiting'], isNull);
    expect(alerts.jobs, 0);
    expect(alerts.jobsLate, isFalse);
    final money = StaffAlerts.fromJson(
        {'payments_waiting': 1, 'refunds_waiting': 2, 'payouts_waiting': 3, 'disputes_open': 4});
    expect(money.payments, 3);
    expect(money.jobs, 7);
  });

  test('open loads the text, send returns the link and drops the row, close drops the text',
      () async {
    final h = harness();
    h.adapter.reply(200, page([messageJson(), messageJson(id: 'm2')]));
    await h.ops.refreshMessages();
    h.adapter.reply(200, messageJson(detail: true));
    await h.ops.openMessage(h.ops.state.messages!.first);
    expect(h.ops.state.messageSelected!.text, startsWith('petitGombo'));

    h.adapter
      ..reply(200, {'whatsapp_url': 'https://wa.me/2250708091011?text=petitGombo'})
      ..reply(200, alertsJson(messages: 1));
    final uri = await h.ops.sendMessage();
    expect(uri!.host, 'wa.me');
    expect(h.adapter.requests[2].path, '/api/v1/staff/messages/m1/send');
    expect(h.ops.state.messages!.map((m) => m.id), ['m2']);
    expect(h.ops.state.busy, isFalse);

    h.ops.closeMessage();
    expect(h.ops.state.messageSelected, isNull);
  });

  test('a stale message leaves the queue and shows the server text', () async {
    final h = harness();
    h.adapter.reply(200, page([messageJson()]));
    await h.ops.refreshMessages();
    h.adapter.reply(200, messageJson(detail: true));
    await h.ops.openMessage(h.ops.state.messages!.single);
    h.adapter
      ..reply(409, {
        'error': 'message_stale',
        'message': "Ce message n'est plus d'actualité : il a été retiré.",
      })
      ..reply(200, alertsJson());
    expect(await h.ops.sendMessage(), isNull);
    expect(h.ops.state.error, "Ce message n'est plus d'actualité : il a été retiré.");
    expect(h.ops.state.messages, isEmpty);
  });

  test('a send that fails offline keeps the message in the queue', () async {
    final h = harness();
    h.adapter.reply(200, page([messageJson()]));
    await h.ops.refreshMessages();
    h.adapter.reply(200, messageJson(detail: true));
    await h.ops.openMessage(h.ops.state.messages!.single);
    h.adapter.offline = true;
    expect(await h.ops.sendMessage(), isNull);
    expect(h.ops.state.error, StaffCopy.offline);
    // Still pending on the server: it must stay visible and sendable.
    expect(h.ops.state.messages!.map((m) => m.id), ['m1']);
    expect(h.ops.state.busy, isFalse);
  });

  test('a message someone else already sent leaves the queue', () async {
    final h = harness();
    h.adapter.reply(200, page([messageJson()]));
    await h.ops.refreshMessages();
    h.adapter.reply(200, messageJson(detail: true));
    await h.ops.openMessage(h.ops.state.messages!.single);
    h.adapter
      ..reply(409, {'error': 'invalid_state', 'message': 'Déjà envoyé.'})
      ..reply(200, alertsJson());
    expect(await h.ops.sendMessage(), isNull);
    expect(h.ops.state.error, 'Déjà envoyé.');
    expect(h.ops.state.messages, isEmpty);
  });

  test('jobs open on payouts, or on disputes for someone who cannot pay', () async {
    final h = harness();
    h.adapter
      ..reply(200, page([payoutJson()]))
      ..reply(200, alertsJson(payouts: 1));
    await h.ops.enter(StaffSection.jobs);
    expect(h.adapter.requests.first.path, '/api/v1/staff/payouts');
    expect(h.ops.state.payouts!.single.jobberPhone, isNull);

    final judge = harness(permissions: ['resolve_dispute']);
    judge.adapter
      ..reply(200, page([disputeJson()]))
      ..reply(200, alertsJson(disputes: 1));
    await judge.ops.enter(StaffSection.jobs);
    expect(judge.ops.state.jobsTab, 'disputes');
    expect(judge.adapter.requests.first.path, '/api/v1/staff/disputes');
  });

  test('paying sends the reference and drops the row and the phone', () async {
    final h = harness();
    h.adapter.reply(200, page([payoutJson()]));
    await h.ops.refreshPayouts();
    h.adapter.reply(200, payoutJson(detail: true));
    await h.ops.openPayout(h.ops.state.payouts!.single);
    expect(h.ops.state.payoutSelected!.jobberPhone, '+2250708091011');

    h.adapter
      ..reply(200, payoutJson())
      ..reply(200, alertsJson());
    expect(await h.ops.payPayout('MOMO-998877'), isTrue);
    final sent = h.adapter.requests[2];
    expect(sent.path, '/api/v1/staff/payouts/po1/pay');
    expect(sent.data, {'reference': 'MOMO-998877'});
    expect(h.ops.state.payouts, isEmpty);
    expect(h.ops.state.payoutSelected, isNull);
  });

  test('a refused payout keeps the detail open with the server text', () async {
    final h = harness();
    h.adapter.reply(200, page([payoutJson()]));
    await h.ops.refreshPayouts();
    h.adapter.reply(200, payoutJson(detail: true));
    await h.ops.openPayout(h.ops.state.payouts!.single);
    h.adapter.reply(400, {
      'error': 'reference_invalid',
      'message': 'Indiquez la référence de la transaction.',
    });
    expect(await h.ops.payPayout('x'), isFalse);
    expect(h.ops.state.error, 'Indiquez la référence de la transaction.');
    expect(h.ops.state.payoutSelected, isNotNull);
    expect(h.ops.state.payouts, hasLength(1));
    h.ops.closePayout();
    expect(h.ops.state.payoutSelected, isNull);
    expect(h.ops.state.error, isNull);
  });

  test('resolving sends the decision and drops the row and the text', () async {
    final h = harness();
    h.adapter.reply(200, page([disputeJson()]));
    await h.ops.selectJobsTab('disputes');
    h.adapter.reply(200, disputeJson(detail: true));
    await h.ops.openDispute(h.ops.state.disputes!.single);
    expect(h.ops.state.disputeSelected!.text, 'Le salon reste sale');
    expect(h.ops.state.disputeSelected!.far, isTrue);

    h.adapter
      ..reply(200, disputeJson())
      ..reply(200, alertsJson());
    expect(await h.ops.resolveDispute('split', 'Moitié faite', jobberXof: 1500), isTrue);
    final sent = h.adapter.requests[2];
    expect(sent.path, '/api/v1/staff/disputes/d1/resolve');
    expect(sent.data, {'outcome': 'split', 'note': 'Moitié faite', 'jobber_xof': 1500});
    expect(h.ops.state.disputes, isEmpty);
    expect(h.ops.state.disputeSelected, isNull);
  });

  test('offline shows the retry message on the list, and reset drops everything', () async {
    final h = harness();
    h.adapter.offline = true;
    await h.ops.refreshMessages();
    expect(h.ops.state.listError, StaffCopy.offline);
    expect(h.ops.state.messages, isEmpty);
    h.ops.reset();
    expect(h.ops.state.messages, isNull);
    expect(h.ops.state.listError, isNull);
  });

  test('an agent with only the message right starts on messages', () async {
    final h = Harness();
    h.queueSignIn(permissions: ['send_message']);
    await h.controller.signIn('ops', 'pw');
    expect(h.controller.state.section, StaffSection.messages);
  });
}
