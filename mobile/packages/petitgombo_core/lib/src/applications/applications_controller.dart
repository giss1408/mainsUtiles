import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import '../offers/offer_copy.dart';
import '../verification/capture.dart';
import 'application_models.dart';
import 'applications_api.dart';
import 'review_models.dart';

const _keep = Object();

String applicationMessage(ApiError e) {
  if (e.isNetwork) return OfferCopy.offline;
  if (e.status == 401) return OfferCopy.sessionExpired;
  return e.message.isNotEmpty ? e.message : OfferCopy.genericError;
}

/// How a check-in ended. Without a position the arrival still counts; the screen says so.
enum CheckInOutcome { withPosition, withoutPosition, failed }

class ApplicationsState {
  const ApplicationsState({
    this.applications,
    this.bookings,
    this.reviews = const {},
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<JobberApplication>? applications;
  final List<JobberBooking>? bookings;

  /// The reviews of the bookings whose screen asked for them, by booking id.
  final Map<String, ReviewState> reviews;
  final bool loading;
  final bool sending;
  final String? error;

  ApplicationsState copyWith({
    List<JobberApplication>? applications,
    List<JobberBooking>? bookings,
    Map<String, ReviewState>? reviews,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      ApplicationsState(
        applications: applications ?? this.applications,
        bookings: bookings ?? this.bookings,
        reviews: reviews ?? this.reviews,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The jobber's applications and bookings: apply, withdraw, follow.
class ApplicationsController extends StateNotifier<ApplicationsState> {
  ApplicationsController({
    required ApplicationsApi api,
    required Session session,
    PositionReader? position,
  })  : _api = api,
        _session = session,
        _position = position,
        super(const ApplicationsState());

  final ApplicationsApi _api;
  final Session _session;
  final PositionReader? _position;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final applications = await _session.authorized(_api.mine);
      final bookings = await _session.authorized(_api.myBookings);
      state = state.copyWith(applications: applications, bookings: bookings, loading: false);
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: applicationMessage(e));
    }
  }

  void clearError() => state = state.copyWith(error: null);

  /// Null when the server refused; [ApplicationsState.error] then holds its words.
  Future<ApplicationReceipt?> apply(String offerId, String message) async {
    if (state.sending) return null;
    state = state.copyWith(sending: true, error: null);
    try {
      final receipt = await _session.authorized((access) => _api.apply(access, offerId, message));
      state = state.copyWith(sending: false);
      return receipt;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return null;
    }
  }

  Future<bool> withdraw(String id) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      final receipt = await _session.authorized((access) => _api.withdraw(access, id));
      final rows = state.applications;
      state = state.copyWith(
        sending: false,
        applications: rows == null
            ? null
            : [for (final row in rows) row.id == id ? row.withStatus(receipt.status) : row],
      );
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }

  /// The exact pin, when the server shows it. Null otherwise; [ApplicationsState.error] then says why.
  /// The address is not kept in the state: the screen holds it only while it is open.
  Future<ReleasedAddress?> address(String bookingId) async {
    state = state.copyWith(error: null);
    try {
      return await _session.authorized((access) => _api.address(access, bookingId));
    } on ApiError catch (e) {
      state = state.copyWith(error: applicationMessage(e));
      return null;
    }
  }

  Future<bool> cancelBooking(String bookingId, String reason) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      await _session.authorized((access) => _api.cancelJobberBooking(access, bookingId, reason));
      state = state.copyWith(sending: false);
      await load();
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }

  /// Runs one change of a job, then reloads. False when the server refused.
  Future<bool> _change(Future<void> Function(String access) call) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      await _session.authorized(call);
      state = state.copyWith(sending: false);
      await load();
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }

  /// "Je suis arrivé(e)". The position is read when the phone allows it; a refusal or a phone
  /// without GPS still checks in, without one.
  Future<CheckInOutcome> checkIn(String bookingId) async {
    if (state.sending) return CheckInOutcome.failed;
    DevicePosition? position;
    try {
      position = await _position?.current();
    } on CaptureException {
      position = null;
    }
    final done = await _change((access) => _api.checkIn(access, bookingId, position: position));
    if (!done) return CheckInOutcome.failed;
    return position == null ? CheckInOutcome.withoutPosition : CheckInOutcome.withPosition;
  }

  Future<bool> checkOut(String bookingId) => _change((access) => _api.checkOut(access, bookingId));

  Future<bool> report(String bookingId, String text, {required bool dispute}) => _change(
        (access) =>
            _api.report(access, bookingId, householder: false, text: text, dispute: dispute),
      );

  Future<void> loadReview(String bookingId) async {
    try {
      final review =
          await _session.authorized((access) => _api.review(access, bookingId, householder: false));
      state = state.copyWith(reviews: {...state.reviews, bookingId: review});
    } on ApiError catch (e) {
      state = state.copyWith(error: applicationMessage(e));
    }
  }

  Future<bool> submitReview(String bookingId, int stars, String comment) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      final review = await _session.authorized(
        (access) => _api.submitReview(access, bookingId,
            householder: false, stars: stars, comment: comment),
      );
      state = state.copyWith(sending: false, reviews: {...state.reviews, bookingId: review});
      await load();
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }
}

final applicationsControllerProvider =
    StateNotifierProvider<ApplicationsController, ApplicationsState>(
  (ref) => ApplicationsController(
    api: ref.watch(applicationsApiProvider),
    session: ref.watch(sessionProvider),
    position: ref.watch(positionReaderProvider),
  ),
);
