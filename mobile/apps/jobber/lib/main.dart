import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'device_capture.dart';

/// The jobber app. Its screens live in petitgombo_core; the camera, which only the apps with
/// verification photos need, is supplied here, and the GPS position, read once when the jobber
/// says "Je suis arrivé(e)".
PetitGomboApp buildApp({
  DeviceDescription device = const DeviceDescription.unknown(),
  List<Override> overrides = const [],
}) =>
    PetitGomboApp(
      role: AppRole.jobber,
      device: device,
      overrides: [
        photoCaptureProvider.overrideWithValue(CameraPhotoCapture()),
        positionReaderProvider.overrideWithValue(GeolocatorPositionReader()),
        ...overrides,
      ],
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp(device: await DeviceDescription.detect()));
}
