// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late MyOffersController controller;

  setUp(() {
    adapter = FakeAdapter();
    controller = MyOffersController(
        api: OffersApi(dioWith(adapter)), session: _SignedIn());
  });

  test('load fills the offers and the categories', () async {
    adapter
      ..reply(200, {
        'can_publish': true,
        'review_hours': 24,
        'offers': [myOfferJson()]
      })
      ..reply(200, {
        'categories': [categoryJson()],
        'limits': limitsJson()
      });
    await controller.load();
    expect(controller.state.data!.offers.single.id, 'o-1');
    expect(controller.state.categories.single.name, 'Ménage');
    expect(controller.state.limits!.maxPay, 100000);
    expect(controller.state.loading, isFalse);
  });

  test('saveDraft without an id creates, with an id updates', () async {
    adapter
      ..reply(201, myOfferJson(id: 'new'))
      ..reply(200, myOfferJson(id: 'new', pay: 4000));
    final created = await controller.saveDraft(draft());
    expect(created!.id, 'new');
    expect(adapter.requests.last.method, 'POST');
    final updated = await controller.saveDraft(draft(pay: 4000), id: 'new');
    expect(updated!.payXof, 4000);
    expect(adapter.requests.last.method, 'PATCH');
    expect(adapter.requests.last.path, '/api/v1/my-offers/new');
  });

  test('publish moves the offer to its new status in the list', () async {
    adapter
      ..reply(200, {
        'can_publish': true,
        'review_hours': 24,
        'offers': [myOfferJson()]
      })
      ..reply(200, {
        'categories': [categoryJson()],
        'limits': limitsJson()
      })
      ..reply(200, myOfferJson(status: 'published'));
    await controller.load();
    final sent = await controller.publish('o-1');
    expect(sent!.status, OfferStatus.published);
    expect(controller.state.data!.offers.single.status, OfferStatus.published);
    expect(controller.state.error, isNull);
  });

  test(
      'a double tap on publish: invalid_state reloads and returns the offer found there',
      () async {
    // Review Focus 5: the first tap was sent and answered; this one finds it already sent.
    adapter
      ..reply(409, {
        'error': 'invalid_state',
        'message': 'Cette offre a déjà été envoyée.'
      })
      ..reply(200, {
        'can_publish': true,
        'review_hours': 24,
        'offers': [myOfferJson(status: 'published')]
      });
    final result = await controller.publish('o-1');
    expect(result!.status, OfferStatus.published);
    expect(controller.state.error, isNull);
    expect(controller.state.sending, isFalse);
    expect(controller.state.data!.offers, hasLength(1));
  });

  test('withdraw, delete and copy keep the list in step', () async {
    adapter
      ..reply(200, {
        'can_publish': true,
        'review_hours': 24,
        'offers': [myOfferJson(), myOfferJson(id: 'o-2')]
      })
      ..reply(200, {
        'categories': [categoryJson()],
        'limits': limitsJson()
      })
      ..reply(200, myOfferJson(status: 'withdrawn'))
      ..reply(204, null)
      ..reply(201, myOfferJson(id: 'copy', status: 'draft'));
    await controller.load();
    await controller.withdraw('o-1');
    expect(controller.state.data!.offers.first.status, OfferStatus.withdrawn);
    await controller.delete('o-2');
    expect(controller.state.data!.offers.map((o) => o.id), ['o-1']);
    final copy = await controller.copy('o-1');
    expect(copy!.id, 'copy');
  });

  test('a network failure keeps the data and sets the retry message', () async {
    adapter
      ..reply(200, {
        'can_publish': true,
        'review_hours': 24,
        'offers': [myOfferJson()]
      })
      ..reply(200, {
        'categories': [categoryJson()],
        'limits': limitsJson()
      });
    await controller.load();
    adapter.offline = true;
    expect(await controller.publish('o-1'), isNull);
    expect(controller.state.error, 'Pas de connexion. Réessayez.');
    expect(controller.state.data!.offers, hasLength(1));
    expect(controller.state.sending, isFalse);
  });
}

class _SignedIn implements Session {
  @override
  Future<T> authorized<T>(Future<T> Function(String access) call) =>
      call('acc');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
