import 'package:flutter_test/flutter_test.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_copy.dart';

import 'support/fixtures.dart';

Future<Harness> signedInOnPayments({List<String> permissions = paymentPermissions}) async {
  final h = Harness();
  h.adapter
    ..reply(200, {'status': 'active'})
    ..reply(200, {'nonce': 'n1'})
    ..reply(200, {'access': 'acc', 'refresh': 'ref'})
    ..reply(200, {'id': 'u1', 'username': 'cashier', 'permissions': permissions})
    ..reply(200, page([paymentJson()]));
  await h.controller.signIn('cashier', 'pw');
  return h;
}

void main() {
  test('a payment agent lands on the payments section and loads the check queue', () async {
    final h = await signedInOnPayments();
    expect(h.controller.state.section, StaffSection.payments);
    expect(h.controller.state.payments!.single.id, 'p1');
    final last = h.adapter.requests.last;
    expect(last.path, '/api/v1/staff/payments');
    expect(last.queryParameters['file'], 'check');
  });

  test('the refund-only agent starts on the refund tab', () async {
    final h = await signedInOnPayments(permissions: ['make_refund']);
    expect(h.controller.state.paymentTab, 'refund');
    expect(h.adapter.requests.last.queryParameters['file'], 'refund');
  });

  test('the refund tab asks for the refund queue', () async {
    final h = await signedInOnPayments();
    h.adapter.reply(200, page([paymentJson(id: 'p2', action: 'refund')]));
    await h.controller.selectPaymentTab('refund');
    expect(h.adapter.requests.last.queryParameters['file'], 'refund');
    expect(h.controller.state.payments!.single.action, 'refund');
  });

  test('open loads the detail and the proof, and close clears them', () async {
    final h = await signedInOnPayments();
    h.adapter
      ..reply(200, paymentJson(detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff]);
    await h.controller.openPayment(h.controller.state.payments!.single);
    expect(h.controller.state.paymentSelected!.reference, 'WAVE-123456');
    expect(h.controller.state.proof, isNotNull);
    expect(h.adapter.requests.last.path, '/api/v1/staff/payments/p1/proof');

    h.controller.closePayment();
    expect(h.controller.state.paymentSelected, isNull);
    expect(h.controller.state.proof, isNull);
  });

  test('confirm sends the checks and drops the row', () async {
    final h = await signedInOnPayments();
    h.adapter
      ..reply(200, paymentJson(detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff])
      ..reply(200, paymentJson());
    await h.controller.openPayment(h.controller.state.payments!.single);
    final done = await h.controller.confirmPayment(amountMatches: true, referenceMatches: true);
    expect(done, isTrue);
    final request = h.adapter.requests.last;
    expect(request.path, '/api/v1/staff/payments/p1/confirm');
    expect(request.data, {'amount_matches': true, 'reference_matches': true});
    expect(h.controller.state.payments, isEmpty);
  });

  test('refuse and refund send their fields', () async {
    final h = await signedInOnPayments();
    h.adapter
      ..reply(200, paymentJson(detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff])
      ..reply(200, paymentJson());
    await h.controller.openPayment(h.controller.state.payments!.single);
    expect(await h.controller.refusePayment('Montant faux'), isTrue);
    expect(h.adapter.requests.last.path, '/api/v1/staff/payments/p1/refuse');
    expect(h.adapter.requests.last.data, {'reason': 'Montant faux'});

    h.adapter.reply(200, page([paymentJson(id: 'p2', action: 'refund')]));
    await h.controller.selectPaymentTab('refund');
    h.adapter
      ..reply(200, paymentJson(id: 'p2', action: 'refund', detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff])
      ..reply(200, paymentJson(id: 'p2', action: 'refund'));
    await h.controller.openPayment(h.controller.state.payments!.single);
    expect(await h.controller.refundPayment('RB-2001'), isTrue);
    expect(h.adapter.requests.last.path, '/api/v1/staff/payments/p2/refund');
    expect(h.adapter.requests.last.data, {'reference': 'RB-2001'});
  });

  test('a 409 reloads the list and shows the server message', () async {
    final h = await signedInOnPayments();
    h.adapter
      ..reply(200, paymentJson(detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff])
      ..reply(409, {'error': 'invalid_state', 'message': 'Ce paiement a déjà été traité.'})
      ..reply(200, page([]));
    await h.controller.openPayment(h.controller.state.payments!.single);
    expect(await h.controller.refusePayment('non'), isFalse);
    expect(h.controller.state.error, 'Ce paiement a déjà été traité.');
    expect(h.controller.state.payments, isEmpty);
    expect(h.controller.state.busy, isFalse);
  });

  test('neither the state nor the storage holds the reference after close', () async {
    final h = await signedInOnPayments();
    h.adapter
      ..reply(200, paymentJson(detail: true))
      ..replyBytes(200, [0xff, 0xd8, 0xff]);
    await h.controller.openPayment(h.controller.state.payments!.single);
    h.controller.closePayment();
    expect(h.controller.state.toString(), isNot(contains('WAVE-123456')));
    expect(h.controller.state.payments!.single.reference, isNull);
    expect(h.store.values.values.join(), isNot(contains('WAVE-123456')));
  });

  test('copy names the section and the history warning in French', () {
    expect(StaffCopy.paymentsTitle, 'Paiements');
    expect(StaffCopy.checkHistory, contains('historique'));
    expect(StaffCopy.permission('verify_payment'), isNot('verify_payment'));
  });
}
