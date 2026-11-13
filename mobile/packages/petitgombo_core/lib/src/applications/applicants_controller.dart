import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import '../offers/my_offers_controller.dart';
import 'application_models.dart';
import 'applications_api.dart';
import 'applications_controller.dart';

const _keep = Object();

class ApplicantsState {
  const ApplicantsState({
    this.applicants,
    this.paymentAvailable = true,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<ApplicantCard>? applicants;

  /// False when staff have set up no payment method: nobody can be accepted.
  final bool paymentAvailable;
  final bool loading;
  final bool sending;
  final String? error;

  ApplicantsState copyWith({
    List<ApplicantCard>? applicants,
    bool? paymentAvailable,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      ApplicantsState(
        applicants: applicants ?? this.applicants,
        paymentAvailable: paymentAvailable ?? this.paymentAvailable,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The applicants of one offer, and accepting one of them.
class ApplicantsController extends StateNotifier<ApplicantsState> {
  ApplicantsController({
    required this.offerId,
    required ApplicationsApi api,
    required Session session,
    required Future<void> Function() onChanged,
  })  : _api = api,
        _session = session,
        _onChanged = onChanged,
        super(const ApplicantsState());

  final String offerId;
  final ApplicationsApi _api;
  final Session _session;

  /// Tells the offers list that this offer changed (it may now be booked).
  final Future<void> Function() _onChanged;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final (rows, available) =
          await _session.authorized((access) => _api.applicants(access, offerId));
      state = state.copyWith(applicants: rows, paymentAvailable: available, loading: false);
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: applicationMessage(e));
    }
  }

  void clearError() => state = state.copyWith(error: null);

  /// Null when the server refused; [ApplicantsState.error] then holds its words.
  Future<BookingSummary?> accept(String applicationId) async {
    if (state.sending) return null;
    state = state.copyWith(sending: true, error: null);
    try {
      final booking = await _session.authorized(
        (access) => _api.accept(access, offerId, applicationId),
      );
      state = state.copyWith(sending: false);
      await load();
      await _onChanged();
      return booking;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: applicationMessage(e));
      // Someone else's tap, the offer's end or a lost verification: show what is true now.
      if (e.status == 409) {
        await load();
        state = state.copyWith(error: applicationMessage(e));
        await _onChanged();
      }
      return null;
    }
  }
}

final applicantsControllerProvider =
    StateNotifierProvider.family<ApplicantsController, ApplicantsState, String>(
  (ref, offerId) => ApplicantsController(
    offerId: offerId,
    api: ref.watch(applicationsApiProvider),
    session: ref.watch(sessionProvider),
    onChanged: () => ref.read(myOffersControllerProvider.notifier).load(),
  ),
);
