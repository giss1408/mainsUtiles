import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'key_value_store.dart';

/// The identity of this phone: an id, a private token for its enrolment
/// application, and an Ed25519 key pair whose private part never leaves it.
class DeviceIdentity {
  DeviceIdentity(this._store);

  static const _idKey = 'device.id';
  static const _tokenKey = 'device.client_token';
  static const _seedKey = 'device.key_seed';

  final KeyValueStore _store;
  final _algorithm = Ed25519();

  Future<String> deviceId() async {
    final existing = await _store.read(_idKey);
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await _store.write(_idKey, id);
    return id;
  }

  Future<String> clientToken() async {
    final existing = await _store.read(_tokenKey);
    if (existing != null) return existing;
    final token = base64UrlEncode(_randomBytes(32));
    await _store.write(_tokenKey, token);
    return token;
  }

  Future<String> publicKeyBase64() async {
    final publicKey = await (await _keyPair()).extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Signs the UTF-8 bytes of [message]; returns the signature in base64.
  Future<String> sign(String message) async {
    final signature = await _algorithm.sign(utf8.encode(message), keyPair: await _keyPair());
    return base64Encode(signature.bytes);
  }

  /// Forgets this identity. The next use creates a new one.
  Future<void> reset() async {
    await _store.delete(_idKey);
    await _store.delete(_tokenKey);
    await _store.delete(_seedKey);
  }

  Future<SimpleKeyPair> _keyPair() async {
    var seed = await _store.read(_seedKey);
    if (seed == null) {
      seed = base64Encode(_randomBytes(32));
      await _store.write(_seedKey, seed);
    }
    return _algorithm.newKeyPairFromSeed(base64Decode(seed));
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
