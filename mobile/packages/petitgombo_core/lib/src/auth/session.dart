import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models.dart';
import 'device_identity.dart';
import 'key_value_store.dart';

/// The signed-in state of an enrolled device.
class Session {
  Session(this._api, this._identity, this._store);

  static const _refreshKey = 'session.refresh';

  final ApiClient _api;
  final DeviceIdentity _identity;
  final KeyValueStore _store;

  String? _access;

  /// The current access token, or null when signed out.
  String? get access => _access;

  /// Signs in with the device key: challenge, signature, tokens.
  Future<Me> signIn() async {
    final deviceId = await _identity.deviceId();
    final nonce = await _api.challenge(deviceId);
    final signature = await _identity.sign('petitgombo-auth:$deviceId:$nonce');
    return _accept(await _api.token(deviceId, nonce, signature));
  }

  /// Restores a previous session. Returns null when there is none or the
  /// server rejects it; network failures are rethrown as [ApiError].
  Future<Me?> restore() async {
    final refresh = await _store.read(_refreshKey);
    if (refresh == null) return null;
    try {
      return await _accept(await _api.refresh(refresh));
    } on ApiError catch (e) {
      if (e.isNetwork) rethrow;
    }
    // The refresh token was rejected; the device key may still be valid.
    try {
      return await signIn();
    } on ApiError catch (e) {
      if (e.isNetwork) rethrow;
      await signOut();
      return null;
    }
  }

  Future<void> signOut() async {
    _access = null;
    await _store.delete(_refreshKey);
  }

  Future<Me> _accept(TokenPair pair) async {
    _access = pair.access;
    await _store.write(_refreshKey, pair.refresh);
    return _api.me(pair.access);
  }
}
