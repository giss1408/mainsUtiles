import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which photo the camera is asked for; it decides the lens and the frame.
enum PhotoKind { idFront, idBack, selfie, addressProof }

/// A photo taken in the app. Held in memory only, never written to the gallery.
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.capturedAt, this.position});

  /// JPEG bytes, already resized for upload.
  final Uint8List bytes;
  final DateTime capturedAt;

  /// Latitude and longitude at capture, when the app had them.
  final (double, double)? position;

  @override
  String toString() => 'CapturedPhoto(${bytes.length} bytes, $capturedAt)';
}

/// A position read from the phone.
class DevicePosition {
  const DevicePosition({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.mocked,
    required this.capturedAt,
  });

  final double lat;
  final double lng;
  final double accuracyM;

  /// True when the phone reports a fake-GPS app.
  final bool mocked;
  final DateTime capturedAt;
}

enum CaptureFailure { permissionDenied, permissionDeniedForever, unavailable }

class CaptureException implements Exception {
  const CaptureException(this.failure);

  final CaptureFailure failure;

  @override
  String toString() => 'CaptureException(${failure.name})';
}

/// Takes a photo with the in-app camera. Implemented by each app that needs it.
abstract class PhotoCapture {
  /// Returns null when the user backs out. Throws [CaptureException] when the
  /// camera cannot be used.
  Future<CapturedPhoto?> take(BuildContext context, {required PhotoKind kind});

  Future<void> openSettings();
}

/// Reads the phone's position. Implemented by each app that needs it.
abstract class PositionReader {
  /// Throws [CaptureException] when the position cannot be read.
  Future<DevicePosition> current();

  Future<void> openSettings();
}

final photoCaptureProvider =
    Provider<PhotoCapture>((ref) => throw UnimplementedError('photoCaptureProvider'));

final positionReaderProvider =
    Provider<PositionReader>((ref) => throw UnimplementedError('positionReaderProvider'));
