import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import '../offers/offer_copy.dart';
import 'application_models.dart';
import 'applications_api.dart';

const _keep = Object();

String applicationMessage(ApiError e) {
  if (e.isNetwork) return OfferCopy.offline;
  if (e.status == 401) return OfferCopy.sessionExpired;
  return e.message.isNotEmpty ? e.message : OfferCopy.genericError;
}

class ApplicationsState {
  const ApplicationsState({
    this.applications,
    this.bookings,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<JobberApplication>? applications;
  final List<JobberBooking>? bookings;
  final bool loading;
  final bool sending;
  final String? error;

  ApplicationsState copyWith({
    List<JobberApplication>? applications,
    List<JobberBooking>? bookings,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      ApplicationsState(
        applications: applications ?? this.applications,
        bookings: bookings ?? this.bookings,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The jobber's applications and bookings: apply, withdraw, follow.
class ApplicationsController extends StateNotifier<ApplicationsState> {
  ApplicationsController({required ApplicationsApi api, required Session session})
      : _api = api,
        _session = session,
        super(const ApplicationsState());

  final ApplicationsApi _api;
  final Session _session;

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
}

final applicationsControllerProvider =
    StateNotifierProvider<ApplicationsController, ApplicationsState>(
  (ref) => ApplicationsController(
    api: ref.watch(applicationsApiProvider),
    session: ref.watch(sessionProvider),
  ),
);
