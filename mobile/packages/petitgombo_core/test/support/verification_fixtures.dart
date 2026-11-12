import 'dart:typed_data';

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

CapturedPhoto photo(int seed, {DateTime? at, (double, double)? position}) => CapturedPhoto(
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, seed, seed, seed]),
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
