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
  Future<bool>? _renewing;

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

  /// Runs [call] with the access token. When the server answers 401 (the
  /// token lasts minutes), renews it once and runs [call] again; if it cannot
  /// be renewed the 401 is rethrown. Calls made at the same moment share one
  /// renewal, because a refresh token presented twice revokes the device's
  /// tokens.
  Future<T> authorized<T>(Future<T> Function(String access) call) async {
    ApiError? rejected;
    final access = _access;
    if (access != null) {
      try {
        return await call(access);
      } on ApiError catch (e) {
        if (e.status != 401) rethrow;
        rejected = e;
      }
    }
    final renewed = await (_renewing ??= _renew().whenComplete(() => _renewing = null));
    final fresh = _access;
    if (!renewed || fresh == null) {
      throw rejected ?? const ApiError(code: 'token_invalid', message: '', status: 401);
    }
    return call(fresh);
  }

  /// False when the server refuses the stored refresh token; network
  /// failures are rethrown.
  Future<bool> _renew() async {
    final refresh = await _store.read(_refreshKey);
    if (refresh == null) return false;
    try {
      final pair = await _api.refresh(refresh);
      _access = pair.access;
      await _store.write(_refreshKey, pair.refresh);
      return true;
    } on ApiError catch (e) {
      if (e.isNetwork) rethrow;
      return false;
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
