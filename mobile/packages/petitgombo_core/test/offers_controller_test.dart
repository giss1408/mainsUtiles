// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late OffersController controller;

  setUp(() {
    adapter = FakeAdapter();
    controller = OffersController(
        api: OffersApi(dioWith(adapter)), session: _SignedIn());
  });

  test('load fills the list and the communes', () async {
    adapter.reply(200, {
      'count': 1,
      'next': null,
      'previous': null,
      'results': [publicOfferJson()],
      'communes': ['Cocody', 'Yopougon'],
    });
    await controller.load();
    expect(controller.state.offers!.single.id, 'p-1');
    expect(controller.state.communes, ['Cocody', 'Yopougon']);
    expect(controller.state.hasMore, isFalse);
  });

  test('choosing a commune reloads the list from the first page', () async {
    adapter
      ..reply(200, {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [publicOfferJson()],
        'communes': ['Cocody']
      })
      ..reply(200, {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [publicOfferJson(id: 'p-2', commune: 'Cocody')],
        'communes': ['Cocody']
      });
    await controller.load();
    await controller.setCommune('Cocody');
    expect(adapter.requests.last.queryParameters,
        {'commune': 'Cocody', 'page': 1});
    expect(controller.state.commune, 'Cocody');
    expect(controller.state.offers!.map((o) => o.id), ['p-2']);
  });

  test('loadMore appends the next page', () async {
    adapter
      ..reply(200, {
        'count': 21,
        'next': 2,
        'previous': null,
        'results': [publicOfferJson()],
        'communes': ['Cocody']
      })
      ..reply(200, {
        'count': 21,
        'next': null,
        'previous': 1,
        'results': [publicOfferJson(id: 'p-21')],
        'communes': ['Cocody']
      });
    await controller.load();
    expect(controller.state.hasMore, isTrue);
    await controller.loadMore();
    expect(controller.state.offers!.map((o) => o.id), ['p-1', 'p-21']);
    expect(controller.state.hasMore, isFalse);
  });

  test('a failed load keeps the list and sets the message', () async {
    adapter.reply(200, {
      'count': 1,
      'next': null,
      'previous': null,
      'results': [publicOfferJson()],
      'communes': []
    });
    await controller.load();
    adapter.offline = true;
    await controller.loadMore(); // no more pages: nothing is requested
    adapter.reply(200, {
      'count': 1,
      'next': null,
      'previous': null,
      'results': [],
      'communes': []
    });
    await controller.setCommune(null);
    adapter.offline = true;
    await controller.setCommune('Yopougon');
    expect(controller.state.offers!.map((o) => o.id),
        ['p-1'] /* kept from before */);
    expect(controller.state.error, 'Pas de connexion. Réessayez.');
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
