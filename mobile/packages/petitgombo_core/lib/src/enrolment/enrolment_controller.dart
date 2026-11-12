import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models.dart';
import '../app/app_role.dart';
import '../auth/device_identity.dart';
import '../auth/key_value_store.dart';
import '../auth/session.dart';
import 'enrolment_state.dart';
import 'phone_format.dart';

const invalidPhoneMessage = 'Numéro de téléphone invalide.';
const offlineMessage = 'Pas de connexion. Réessayez.';
const genericErrorMessage = 'Une erreur est survenue. Réessayez.';

/// Drives device enrolment: apply, wait for staff, type the confirmation number.
class EnrolmentController extends StateNotifier<EnrolmentState> {
  EnrolmentController({
    required ApiClient api,
    required DeviceIdentity identity,
    required Session session,
    required KeyValueStore store,
    required AppRole role,
    required String deviceModel,
    required String platform,
  })  : _api = api,
        _identity = identity,
        _session = session,
        _store = store,
        _role = role,
        _deviceModel = deviceModel,
        _platform = platform,
        super(const EnrolmentInitial());

  static const applicationIdKey = 'enrolment.application_id';

  final ApiClient _api;
  final DeviceIdentity _identity;
  final Session _session;
  final KeyValueStore _store;
  final AppRole _role;
  final String _deviceModel;
  final String _platform;

  /// Restores the state after the app was closed.
  Future<void> resume() => refresh();

  Future<void> submitPhone(String input) async {
    final phone = normaliseIvorianPhone(input);
    if (phone == null) {
      state = const EnrolmentFailure(invalidPhoneMessage, previous: EnrolmentInitial());
      return;
    }
    state = const EnrolmentSubmitting();
    try {
      final status = await _api.apply(
        phone: phone,
        role: _role,
        deviceId: await _identity.deviceId(),
        deviceModel: _deviceModel,
        platform: _platform,
        publicKey: await _identity.publicKeyBase64(),
        clientToken: await _identity.clientToken(),
      );
      await _store.write(applicationIdKey, status.id);
      await _show(status);
    } on ApiError catch (e) {
      state = EnrolmentFailure(_messageFor(e), previous: const EnrolmentInitial());
    }
  }

  /// Asks the server where the application stands.
  Future<void> refresh() async {
    final id = await _store.read(applicationIdKey);
    if (id == null) {
      state = const EnrolmentInitial();
      return;
    }
    final shown = _visible(state);
    try {
      await _show(await _api.status(id, await _identity.clientToken()));
    } on ApiError catch (e) {
      if (e.status == 404) {
        await startOver();
      } else {
        state = EnrolmentFailure(_messageFor(e), previous: shown);
      }
    }
  }

  Future<void> submitCode(String code) async {
    final id = await _store.read(applicationIdKey);
    if (id == null) {
      state = const EnrolmentInitial();
      return;
    }
    try {
      await _api.confirm(id, await _identity.clientToken(), code.trim());
      state = EnrolmentDone(await _session.signIn());
    } on ApiError catch (e) {
      switch (e.code) {
        case 'code_invalid' || 'code_replaced' || 'code_expired':
          state = EnrolmentAwaitingCode(errorMessage: e.message);
        case 'locked':
          state = const EnrolmentLocked();
        case 'invalid_state':
          await refresh();
        default:
          state = EnrolmentFailure(_messageFor(e), previous: const EnrolmentAwaitingCode());
      }
    }
  }

  /// Abandons the current application. The device identity is kept.
  Future<void> startOver() async {
    await _store.delete(applicationIdKey);
    state = const EnrolmentInitial();
  }

  Future<void> _show(EnrolmentStatus status) async {
    switch (status.status) {
      case 'pending':
        state = EnrolmentPending(status.responseHours);
      case 'held':
        state = EnrolmentHeld(status.reason);
      case 'awaiting_code':
        state = const EnrolmentAwaitingCode();
      case 'refused':
        state = EnrolmentRefused(status.reason);
      case 'locked':
        state = const EnrolmentLocked();
      case 'expired':
        state = const EnrolmentExpired();
      case 'completed':
        state = EnrolmentDone(await _session.signIn());
      default:
        state = EnrolmentPending(status.responseHours);
    }
  }

  EnrolmentState _visible(EnrolmentState current) => switch (current) {
        EnrolmentFailure(:final previous) => previous,
        EnrolmentSubmitting() => const EnrolmentInitial(),
        _ => current,
      };

  String _messageFor(ApiError e) {
    if (e.isNetwork) return offlineMessage;
    return e.message.isNotEmpty ? e.message : genericErrorMessage;
  }
}
