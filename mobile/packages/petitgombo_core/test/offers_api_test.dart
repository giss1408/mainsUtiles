import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/offer_fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late OffersApi api;

  setUp(() {
    adapter = FakeAdapter();
    api = OffersApi(dioWith(adapter));
  });

  test('categories returns the catalogue and the limits', () async {
    adapter.reply(200, {
      'categories': [categoryJson()],
      'limits': limitsJson(),
    });
    final (categories, limits) = await api.categories('acc');
    expect(adapter.requests.single.path, '/api/v1/offer-categories');
    expect(categories.single.durationsMinutes, [120, 180, 240]);
    expect(categories.single.suggestedPayMax, 5000);
    expect(limits.earliestStart, (6, 0));
    expect(limits.latestEnd, (19, 0));
    expect(limits.maxPay, 100000);
  });

  test('myOffers parses can_publish, review hours and offers', () async {
    adapter.reply(200, {
      'can_publish': true,
      'review_hours': 24,
      'offers': [myOfferJson(status: 'in_review')],
    });
    final mine = await api.myOffers('acc');
    expect(mine.canPublish, isTrue);
    expect(mine.reviewHours, 24);
    expect(mine.offers.single.status, OfferStatus.inReview);
    expect(mine.offers.single.startsAt.isUtc, isFalse);
  });

  test('createDraft posts the draft with the start in UTC', () async {
    adapter.reply(201, myOfferJson());
    final offer = await api.createDraft('acc', draft());
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/my-offers');
    expect(request.data, {
      'category_id': 1,
      'duties': ['Dépoussiérer'],
      'starts_at': '2026-11-14T08:00:00.000Z',
      'duration_minutes': 180,
      'pay_xof': 3500,
      'note': '',
    });
    expect(offer.id, 'o-1');
  });

  test('send, withdraw and copy call their own routes', () async {
    adapter
      ..reply(200, myOfferJson(status: 'published'))
      ..reply(200, myOfferJson(status: 'withdrawn'))
      ..reply(201, myOfferJson(status: 'draft'));
    expect((await api.send('acc', 'o-1')).status, OfferStatus.published);
    expect((await api.withdraw('acc', 'o-1')).status, OfferStatus.withdrawn);
    expect((await api.copy('acc', 'o-1')).status, OfferStatus.draft);
    expect(adapter.requests.map((r) => r.path), [
      '/api/v1/my-offers/o-1/send',
      '/api/v1/my-offers/o-1/withdraw',
      '/api/v1/my-offers/o-1/copy',
    ]);
  });

  test('deleteDraft sends DELETE', () async {
    adapter.reply(204, null);
    await api.deleteDraft('acc', 'o-1');
    expect(adapter.requests.single.method, 'DELETE');
  });

  test('offers passes the commune and the page, and parses the page', () async {
    adapter.reply(200, {
      'count': 1,
      'next': null,
      'previous': null,
      'results': [publicOfferJson()],
      'communes': ['Cocody', 'Yopougon'],
    });
    final page = await api.offers('acc', commune: 'Cocody', page: 2);
    expect(adapter.requests.single.queryParameters, {'commune': 'Cocody', 'page': 2});
    expect(page.offers.single.commune, 'Cocody');
    expect(page.communes, ['Cocody', 'Yopougon']);
    expect(page.hasMore, isFalse);
  });

  test('a 409 too_many_offers becomes an ApiError with its message', () async {
    adapter.reply(409, {
      'error': 'too_many_offers',
      'message': 'Vous avez déjà 3 offres en cours. Retirez-en une pour en publier une autre.',
    });
    await expectLater(
      api.send('acc', 'o-1'),
      throwsA(isA<ApiError>()
          .having((e) => e.code, 'code', 'too_many_offers')
          .having((e) => e.status, 'status', 409)),
    );
  });
}
