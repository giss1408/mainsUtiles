import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

void main() {
  test('identity is created once and persists', () async {
    final store = InMemoryKeyValueStore();
    final a = DeviceIdentity(store);
    final b = DeviceIdentity(store);
    expect(await a.deviceId(), await b.deviceId());
    expect(await a.clientToken(), await b.clientToken());
    expect(await a.publicKeyBase64(), await b.publicKeyBase64());
    expect(base64Decode(await a.publicKeyBase64()).length, 32);
    expect((await a.clientToken()).length, greaterThanOrEqualTo(32));
  });

  test('signature verifies with the public key', () async {
    final identity = DeviceIdentity(InMemoryKeyValueStore());
    const message = 'petitgombo-auth:device:nonce';
    final signature = base64Decode(await identity.sign(message));
    final publicKey = SimplePublicKey(
      base64Decode(await identity.publicKeyBase64()),
      type: KeyPairType.ed25519,
    );
    final valid = await Ed25519().verify(
      utf8.encode(message),
      signature: Signature(signature, publicKey: publicKey),
    );
    expect(valid, isTrue);
  });

  test('reset creates a new identity', () async {
    final identity = DeviceIdentity(InMemoryKeyValueStore());
    final before = await identity.deviceId();
    await identity.reset();
    expect(await identity.deviceId(), isNot(before));
  });
}
