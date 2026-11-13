import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'device_capture.dart';
import 'gallery_picker.dart';

/// The householder app. Its screens live in petitgombo_core; the camera and
/// the GPS, which only this app needs, are supplied here.
PetitGomboApp buildApp({
  DeviceDescription device = const DeviceDescription.unknown(),
  List<Override> overrides = const [],
}) =>
    PetitGomboApp(
      role: AppRole.householder,
      device: device,
      overrides: [
        photoCaptureProvider.overrideWithValue(CameraPhotoCapture()),
        positionReaderProvider.overrideWithValue(GeolocatorPositionReader()),
        proofPickerProvider.overrideWithValue(GalleryProofPicker()),
        ...overrides,
      ],
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp(device: await DeviceDescription.detect()));
}
