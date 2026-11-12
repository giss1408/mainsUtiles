import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:petitgombo_core/petitgombo_core.dart';

Map<String, dynamic> checklistJson({
  String tier = 'H0',
  Map<String, dynamic>? identity,
  Map<String, dynamic>? address,
  Map<String, dynamic>? homeLocation,
}) =>
    {
      'tier': tier,
      'review_hours': 24,
      'communes': ['Cocody', 'Yopougon'],
      'identity': identity ?? {'status': 'not_started', 'reason': ''},
      'address': address ??
          {
            'status': 'not_started',
            'reason': '',
            'commune': '',
            'quartier': '',
            'expires_at': null
          },
      'home_location': homeLocation ?? {'status': 'not_started', 'reason': ''},
    };

VerificationChecklist checklist({
  String tier = 'H0',
  Map<String, dynamic>? identity,
  Map<String, dynamic>? address,
  Map<String, dynamic>? homeLocation,
}) =>
    VerificationChecklist.fromJson(
      checklistJson(tier: tier, identity: identity, address: address, homeLocation: homeLocation),
    );

/// A real one-pixel JPEG, so screens can show it.
final Uint8List tinyJpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP////////////////////////////////////////////////////////////'
  '//////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
);

CapturedPhoto photo(int seed, {DateTime? at, (double, double)? position}) => CapturedPhoto(
      bytes: Uint8List.fromList([...tinyJpeg, seed]),
      capturedAt: at ?? DateTime.utc(2026, 11, 12, 9),
      position: position,
    );

DevicePosition homePosition({bool mocked = false}) => DevicePosition(
      lat: 5.3599,
      lng: -3.9871,
      accuracyM: 12.4,
      mocked: mocked,
      capturedAt: DateTime.utc(2026, 11, 12, 9),
    );

/// Returns a fixed position, or throws the failure it was given.
class FakePositionReader implements PositionReader {
  CaptureFailure? failure;
  int reads = 0;
  int settingsOpened = 0;

  @override
  Future<DevicePosition> current() async {
    reads++;
    if (failure != null) throw CaptureException(failure!);
    return homePosition();
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// Hands out photos without a camera and records what was asked for.
class FakePhotoCapture implements PhotoCapture {
  final List<PhotoKind> asked = [];
  CaptureFailure? failure;
  bool cancel = false;
  int settingsOpened = 0;

  @override
  Future<CapturedPhoto?> take(BuildContext context, {required PhotoKind kind}) async {
    asked.add(kind);
    if (failure != null) throw CaptureException(failure!);
    return cancel ? null : photo(asked.length);
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// A signed-in session that needs no network.
class SignedInSession implements Session {
  int signOuts = 0;

  @override
  String? get access => 'acc';

  @override
  Future<T> authorized<T>(Future<T> Function(String access) call) => call('acc');

  @override
  Future<Me?> restore() async => const Me(id: 'u-1', phone: '+2250505050505', role: 'householder');

  @override
  Future<Me> signIn() async => const Me(id: 'u-1', phone: '+2250505050505', role: 'householder');

  @override
  Future<void> signOut() async => signOuts++;
}
