// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/fake_adapter.dart';

const base = '/api/v1';

class FakePosition implements PositionReader {
  FakePosition({this.failure});

  final CaptureFailure? failure;

  @override
  Future<DevicePosition> current() async {
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

void main() {
  late FakeAdapter adapter;
  late Session session;
  late ApplicationsApi api;
  late BookingController householder;
  late int changed;

  ApplicationsController jobber([PositionReader? position]) =>
      ApplicationsController(api: api, session: session, position: position);

  void reloads() => adapter
    ..reply(200, {'results': []})
    ..reply(200, {
      'results': [jobberBookingJson()]
    });

  setUp(() async {
    adapter = FakeAdapter();
    final store = InMemoryKeyValueStore();
    final dio = dioWith(adapter);
    session = Session(ApiClient(dio), DeviceIdentity(store), store);
    adapter
      ..reply(200, {'nonce': 'n-1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(200, {'id': 'u-1', 'phone': '+2250505050505', 'role': 'jobber', 'device_id': 'd'});
    await session.signIn();
    adapter.requests.clear();
    api = ApplicationsApi(dio);
    changed = 0;
    householder = BookingController(
      offerId: 'o-1',
      api: api,
      session: session,
      onChanged: () async => changed++,
    );
  });

  test('the models parse the new fields', () {
    final job = JobberBooking.fromJson({
      ...jobberBookingJson(),
      'status': 'completed',
      'checked_in_at': '2026-11-14T08:05:00Z',
      'checked_out_at': '2026-11-14T11:00:00Z',
      'auto_confirm_at': '2026-11-15T11:00:00Z',
      'payout': 'due',
      'reviewable': true,
    });
    expect(job.checkinFrom.toUtc(), DateTime.utc(2026, 11, 14, 7, 30));
    expect(job.checkedInAt!.toUtc(), DateTime.utc(2026, 11, 14, 8, 5));
    expect(job.checkedOutAt, isNotNull);
    expect(job.autoConfirmAt!.toUtc(), DateTime.utc(2026, 11, 15, 11));
    expect(job.payout, 'due');
    expect(job.reviewable, isTrue);

    final old = JobberBooking.fromJson(jobberBookingJson()
      ..remove('checkin_from')
      ..remove('payout')
      ..remove('reviewable'));
    expect(old.checkinFrom.toUtc(), DateTime.utc(2026, 11, 14, 7, 30));
    expect(old.payout, 'none');
    expect(old.reviewable, isFalse);

    final detail = BookingDetail.fromJson({
      ...bookingDetailJson(status: 'completion_pending'),
      'checked_in_at': '2026-11-14T08:05:00Z',
      'checked_out_at': '2026-11-14T11:00:00Z',
      'auto_confirm_at': '2026-11-15T11:00:00Z',
      'reviewable': false,
      'jobber_rating': 4.5,
    });
    expect(detail.checkedInAt, isNotNull);
    expect(detail.autoConfirmAt!.toUtc(), DateTime.utc(2026, 11, 15, 11));
    expect(detail.jobberRating, 4.5);
    expect(detail.reportable, isTrue);
    expect(BookingDetail.fromJson(bookingDetailJson()).reportable, isFalse);
  });

  test('theirs is null until published', () {
    final hidden = ReviewState.fromJson({
      'mine': {'stars': 4, 'comment': 'Bien'},
      'theirs': null,
    });
    expect(hidden.mine!.stars, 4);
    expect(hidden.mine!.comment, 'Bien');
    expect(hidden.theirs, isNull);
    final both = ReviewState.fromJson({
      'mine': {'stars': 4, 'comment': 'Bien'},
      'theirs': {'stars': 5, 'comment': ''},
    });
    expect(both.theirs!.stars, 5);
  });

  test('check-in sends the position and reloads', () async {
    adapter.reply(200, {'id': 'b-1', 'status': 'checked_in'});
    reloads();
    final controller = jobber(FakePosition());
    expect(await controller.checkIn('b-1'), CheckInOutcome.withPosition);
    expect(adapter.requests.first.path, '$base/my-bookings/b-1/check-in');
    expect(adapter.requests.first.data, {'lat': 5.36, 'lng': -3.98, 'accuracy_m': 12.0});
    expect(adapter.requests.map((r) => r.path).skip(1),
        ['$base/my-applications', '$base/my-bookings']);
    expect(controller.state.bookings!.single.id, 'b-1');
  });

  test('check-in survives a refused permission and a phone without a reader', () async {
    for (final reader in [FakePosition(failure: CaptureFailure.permissionDenied), null]) {
      adapter.requests.clear();
      adapter.reply(200, {'id': 'b-1', 'status': 'checked_in'});
      reloads();
      expect(await jobber(reader).checkIn('b-1'), CheckInOutcome.withoutPosition);
      expect(adapter.requests.first.data, <String, dynamic>{});
    }
  });

  test('a refused check-in shows the server text', () async {
    adapter.reply(409, {
      'error': 'checkin_too_early',
      'message': 'Tu pourras confirmer ton arrivée peu avant le début.',
    });
    final controller = jobber(FakePosition());
    expect(await controller.checkIn('b-1'), CheckInOutcome.failed);
    expect(controller.state.error, 'Tu pourras confirmer ton arrivée peu avant le début.');
    expect(controller.state.sending, isFalse);
  });

  test('check-out and the jobber report send their bodies and reload', () async {
    final controller = jobber();
    adapter.reply(200, {'id': 'b-1', 'status': 'completion_pending'});
    reloads();
    expect(await controller.checkOut('b-1'), isTrue);
    expect(adapter.requests.first.path, '$base/my-bookings/b-1/check-out');
    expect(adapter.requests.length, 3);

    adapter.requests.clear();
    adapter.reply(201, {'id': 'r-1', 'kind': 'concern', 'booking_status': 'completion_pending'});
    reloads();
    expect(await controller.report('b-1', 'Le chien mord', dispute: false), isTrue);
    expect(adapter.requests.first.path, '$base/my-bookings/b-1/report');
    expect(adapter.requests.first.data, {'text': 'Le chien mord', 'dispute': false});
    expect(adapter.requests.length, 3);
  });

  test('confirm and the householder report send their bodies and reload', () async {
    adapter
      ..reply(200, {'id': 'b-1', 'status': 'completed'})
      ..reply(200, bookingDetailJson(status: 'completed', cancellable: false));
    expect(await householder.confirmDone(), isTrue);
    expect(adapter.requests.first.path, '$base/my-offers/o-1/booking/confirm');
    expect(adapter.requests.last.path, '$base/my-offers/o-1/booking');
    expect(householder.state.detail!.status, 'completed');
    expect(changed, 1);

    adapter.requests.clear();
    adapter
      ..reply(201, {'id': 'r-1', 'kind': 'dispute', 'booking_status': 'disputed'})
      ..reply(200, bookingDetailJson(status: 'disputed', cancellable: false));
    expect(await householder.report('Rien de fait', dispute: true), isTrue);
    expect(adapter.requests.first.path, '$base/my-offers/o-1/booking/report');
    expect(adapter.requests.first.data, {'text': 'Rien de fait', 'dispute': true});
    expect(householder.state.detail!.status, 'disputed');
  });

  test('a refused confirmation shows the server text', () async {
    adapter.reply(
        409, {'error': 'invalid_state', 'message': 'Cette demande ne peut plus être modifiée.'});
    expect(await householder.confirmDone(), isFalse);
    expect(householder.state.error, 'Cette demande ne peut plus être modifiée.');
    expect(changed, 0);
  });

  test('reviews load and submit on both sides', () async {
    adapter.reply(200, {'mine': null, 'theirs': null});
    await householder.loadReview();
    expect(adapter.requests.single.path, '$base/my-offers/o-1/booking/review');
    expect(householder.state.review!.mine, isNull);

    adapter.requests.clear();
    adapter
      ..reply(201, {
        'mine': {'stars': 4, 'comment': 'Sérieux'},
        'theirs': null,
      })
      ..reply(200, bookingDetailJson(status: 'completed', cancellable: false));
    expect(await householder.submitReview(4, 'Sérieux'), isTrue);
    expect(adapter.requests.first.data, {'stars': 4, 'comment': 'Sérieux'});
    expect(householder.state.review!.mine!.stars, 4);
    expect(householder.state.review!.theirs, isNull);

    final controller = jobber();
    adapter.requests.clear();
    adapter.reply(201, {
      'mine': {'stars': 5, 'comment': ''},
      'theirs': {'stars': 4, 'comment': 'Sérieux'},
    });
    reloads();
    expect(await controller.submitReview('b-1', 5, ''), isTrue);
    expect(adapter.requests.first.path, '$base/my-bookings/b-1/review');
    expect(controller.state.reviews['b-1']!.theirs!.comment, 'Sérieux');

    adapter.requests.clear();
    adapter.reply(200, {'mine': null, 'theirs': null});
    await controller.loadReview('b-2');
    expect(adapter.requests.single.path, '$base/my-bookings/b-2/review');
    expect(controller.state.reviews.keys, containsAll(['b-1', 'b-2']));
  });

  test('a refused review shows the server text', () async {
    adapter.reply(400, {
      'error': 'message_contact_details',
      'message': 'Ne mets pas de numéro ni de contact dans ton message.',
    });
    final controller = jobber();
    expect(await controller.submitReview('b-1', 5, '07 08 09 10 11'), isFalse);
    expect(controller.state.error, 'Ne mets pas de numéro ni de contact dans ton message.');
    expect(controller.state.reviews, isEmpty);
  });

  test('offline shows the retry message', () async {
    adapter.offline = true;
    final controller = jobber();
    expect(await controller.checkOut('b-1'), isFalse);
    expect(controller.state.error, OfferCopy.offline);
    expect(await householder.confirmDone(), isFalse);
    expect(householder.state.error, OfferCopy.offline);
  });
}
