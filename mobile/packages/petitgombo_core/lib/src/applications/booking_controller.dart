import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import '../offers/my_offers_controller.dart';
import '../verification/capture.dart';
import 'application_models.dart';
import 'applications_api.dart';
import 'applications_controller.dart';

const _keep = Object();

class BookingState {
  const BookingState({
    this.detail,
    this.photo,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until loaded, and again when the offer has no live booking.
  final BookingDetail? detail;

  /// The jobber's verified photo, once the payment is confirmed and the screen asked for it.
  final Uint8List? photo;
  final bool loading;
  final bool sending;
  final String? error;

  BookingState copyWith({
    Object? detail = _keep,
    Uint8List? photo,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      BookingState(
        detail: identical(detail, _keep) ? this.detail : detail as BookingDetail?,
        photo: photo ?? this.photo,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The booking of one offer, as its householder follows it: pay, wait, cancel.
class BookingController extends StateNotifier<BookingState> {
  BookingController({
    required this.offerId,
    required ApplicationsApi api,
    required Session session,
    required Future<void> Function() onChanged,
  })  : _api = api,
        _session = session,
        _onChanged = onChanged,
        super(const BookingState());

  final String offerId;
  final ApplicationsApi _api;
  final Session _session;

  /// Tells the offers list that this offer changed.
  final Future<void> Function() _onChanged;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final detail = await _session.authorized((access) => _api.booking(access, offerId));
      state = state.copyWith(detail: detail, loading: false);
    } on ApiError catch (e) {
      // No live booking any more (it was cancelled or expired): nothing to show, nothing wrong.
      state = e.status == 404
          ? state.copyWith(detail: null, loading: false)
          : state.copyWith(loading: false, error: applicationMessage(e));
    }
  }

  void clearError() => state = state.copyWith(error: null);

  /// False when the server refused; [BookingState.error] then holds its words.
  Future<bool> submitProof({
    required int methodId,
    required String reference,
    required CapturedPhoto screenshot,
  }) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      await _session.authorized(
        (access) => _api.submitProof(
          access,
          offerId,
          methodId: methodId,
          reference: reference,
          screenshot: screenshot,
        ),
      );
      state = state.copyWith(sending: false);
      await load();
      await _onChanged();
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }

  Future<bool> cancel(String reason) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      await _session.authorized((access) => _api.cancelBooking(access, offerId, reason));
      state = state.copyWith(sending: false);
      await load();
      await _onChanged();
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      return false;
    }
  }

  Future<void> loadPhoto() async {
    try {
      final bytes = await _session.authorized((access) => _api.bookingPhoto(access, offerId));
      state = state.copyWith(photo: bytes);
    } on ApiError {
      // The initials are shown instead; nothing to report.
    }
  }
}

final bookingControllerProvider =
    StateNotifierProvider.family<BookingController, BookingState, String>(
  (ref, offerId) => BookingController(
    offerId: offerId,
    api: ref.watch(applicationsApiProvider),
    session: ref.watch(sessionProvider),
    onChanged: () => ref.read(myOffersControllerProvider.notifier).load(),
  ),
);
