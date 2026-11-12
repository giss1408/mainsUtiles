import 'package:petitgombo_core/petitgombo_core.dart';

import 'staff_api.dart';

/// The signed-in state of a staff phone. Tokens live in memory only and the
/// password is never kept: closing the app signs out.
class StaffSession {
  StaffSession(this._api, this._identity, {required this.deviceModel, required this.platform});

  final StaffApi _api;
  final DeviceIdentity _identity;
  final String deviceModel;
  final String platform;

  TokenPair? _tokens;

  /// The current access token, or null when signed out.
  String? get access => _tokens?.access;

  /// Registers this phone when the server does not know it, then signs in with
  /// the password and the device key. Throws [ApiError] `device_pending` while
  /// an administrator has not activated the phone.
  Future<StaffMe> signIn(String username, String password) async {
    var status = await _register(username, password);
    if (status == 'revoked') {
      // A revoked phone cannot come back; it applies again as a new device.
      await _identity.reset();
      status = await _register(username, password);
    }
    if (status != 'active') {
      throw const ApiError(code: 'device_pending', message: '');
    }
    final deviceId = await _identity.deviceId();
    final nonce = await _api.challenge(deviceId);
    final signature = await _identity.sign('petitgombo-auth:$deviceId:$nonce');
    final tokens = await _api.login(
      username: username,
      password: password,
      deviceId: deviceId,
      nonce: nonce,
      signature: signature,
    );
    final me = await _api.me(tokens.access);
    _tokens = tokens;
    return me;
  }

  void signOut() => _tokens = null;

  Future<String> _register(String username, String password) async => _api.registerDevice(
        username: username,
        password: password,
        deviceId: await _identity.deviceId(),
        deviceModel: deviceModel,
        platform: platform,
        publicKey: await _identity.publicKeyBase64(),
      );
}
