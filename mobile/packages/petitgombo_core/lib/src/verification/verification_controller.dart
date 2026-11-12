import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import 'capture.dart';
import 'verification_api.dart';
import 'verification_copy.dart';
import 'verification_models.dart';

const _keep = Object();

class VerificationState {
  const VerificationState({
    this.checklist,
    this.loading = false,
    this.sending = false,
    this.error,
    this.captureFailure,
  });

  /// Null until the first successful load.
  final VerificationChecklist? checklist;
  final bool loading;
  final bool sending;

  /// A French message for the current screen.
  final String? error;

  /// Why the position could not be read, so the screen can offer the settings.
  final CaptureFailure? captureFailure;

  VerificationState copyWith({
    VerificationChecklist? checklist,
    bool? loading,
    bool? sending,
    Object? error = _keep,
    Object? captureFailure = _keep,
  }) =>
      VerificationState(
        checklist: checklist ?? this.checklist,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
        captureFailure: identical(captureFailure, _keep)
            ? this.captureFailure
            : captureFailure as CaptureFailure?,
      );
}

/// Loads the verification checklist and sends each step.
class VerificationController extends StateNotifier<VerificationState> {
  VerificationController({
    required VerificationApi api,
    required Session session,
    required PositionReader position,
  })  : _api = api,
        _session = session,
        _position = position,
        super(const VerificationState());

  final VerificationApi _api;
  final Session _session;
  final PositionReader _position;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final checklist = await _session.authorized(_api.checklist);
      state = state.copyWith(checklist: checklist, loading: false);
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: _message(e, VerificationCopy.offline));
    }
  }

  void clearError() => state = state.copyWith(error: null, captureFailure: null);

  Future<bool> sendIdentity({
    required String documentType,
    required CapturedPhoto front,
    required CapturedPhoto back,
    required CapturedPhoto selfie,
  }) =>
      _send(
        (access) => _api.submitIdentity(
          access,
          documentType: documentType,
          front: front,
          back: back,
          selfie: selfie,
        ),
        offline: VerificationCopy.offlinePhotosKept,
      );

  Future<bool> sendAddress({
    required String documentType,
    required CapturedPhoto photo,
    required String commune,
    required String quartier,
  }) =>
      _send(
        (access) => _api.submitAddress(
          access,
          documentType: documentType,
          photo: photo,
          commune: commune,
          quartier: quartier,
        ),
        offline: VerificationCopy.offlinePhotosKept,
      );

  /// Reads the phone's position, then sends it.
  Future<bool> recordHome() async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null, captureFailure: null);
    final DevicePosition position;
    try {
      position = await _position.current();
    } on CaptureException catch (e) {
      state = state.copyWith(
        sending: false,
        error: VerificationCopy.positionFailure(e.failure),
        captureFailure: e.failure,
      );
      return false;
    }
    state = state.copyWith(sending: false);
    return _send(
      (access) => _api.recordHomeLocation(access, position),
      offline: VerificationCopy.offline,
    );
  }

  Future<bool> _send(
    Future<VerificationChecklist> Function(String access) call, {
    required String offline,
  }) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      final checklist = await _session.authorized(call);
      state = state.copyWith(checklist: checklist, sending: false);
      return true;
    } on ApiError catch (e) {
      if (e.code == 'invalid_state' && await _alreadySent()) return true;
      state = state.copyWith(sending: false, error: _message(e, offline));
      return false;
    }
  }

  /// The server says the step is already sent. That happens when an earlier
  /// attempt arrived but its answer was lost: reload and carry on.
  Future<bool> _alreadySent() async {
    try {
      final checklist = await _session.authorized(_api.checklist);
      state = state.copyWith(checklist: checklist, sending: false, error: null);
      return true;
    } on ApiError {
      return false;
    }
  }

  String _message(ApiError e, String offline) {
    if (e.isNetwork) return offline;
    if (e.status == 401) return VerificationCopy.sessionExpired;
    return e.message.isNotEmpty ? e.message : VerificationCopy.genericError;
  }
}

final verificationApiProvider =
    Provider<VerificationApi>((ref) => VerificationApi(ref.watch(dioProvider)));

final verificationControllerProvider =
    StateNotifierProvider<VerificationController, VerificationState>(
  (ref) => VerificationController(
    api: ref.watch(verificationApiProvider),
    session: ref.watch(sessionProvider),
    position: ref.watch(positionReaderProvider),
  ),
);
