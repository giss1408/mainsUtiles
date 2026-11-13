import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:petitgombo_core/petitgombo_core.dart';

/// Longest side of an uploaded photo, in pixels. Legible, and light on mobile data.
const int _maxSide = 1600;
const int _jpegQuality = 80;

/// Resizes and re-encodes a camera JPEG. Runs in a background isolate.
Uint8List _prepare(Uint8List original) {
  final decoded = img.decodeJpg(original);
  if (decoded == null) return original;
  var image = img.bakeOrientation(decoded);
  if (image.width > _maxSide || image.height > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide)
        : img.copyResize(image, height: _maxSide);
  }
  return img.encodeJpg(image, quality: _jpegQuality);
}

/// The in-app camera. Photos stay in memory: nothing is saved to the gallery,
/// and no picture can be picked from it.
class CameraPhotoCapture implements PhotoCapture {
  @override
  Future<CapturedPhoto?> take(BuildContext context, {required PhotoKind kind}) async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException {
      throw const CaptureException(CaptureFailure.unavailable);
    }
    if (cameras.isEmpty) throw const CaptureException(CaptureFailure.unavailable);
    final wanted = kind == PhotoKind.selfie ? CameraLensDirection.front : CameraLensDirection.back;
    final camera =
        cameras.firstWhere((c) => c.lensDirection == wanted, orElse: () => cameras.first);
    if (!context.mounted) return null;

    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CameraPage(camera: camera, kind: kind),
      ),
    );
    if (result is CaptureException) throw result;
    if (result is! Uint8List) return null;

    final capturedAt = DateTime.now();
    final bytes = await compute(_prepare, result);
    return CapturedPhoto(bytes: bytes, capturedAt: capturedAt, position: await _lastPosition());
  }

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Where the phone last knew it was, if location is already allowed. Never prompts.
  Future<(double, double)?> _lastPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : (position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }
}

class _CameraPage extends StatefulWidget {
  const _CameraPage({required this.camera, required this.kind});

  final CameraDescription camera;
  final PhotoKind kind;

  @override
  State<_CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<_CameraPage> {
  late final CameraController _controller = CameraController(
    widget.camera,
    ResolutionPreset.high,
    enableAudio: false,
    imageFormatGroup: ImageFormatGroup.jpeg,
  );
  bool _ready = false;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _ready = true);
    } on CameraException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(
        CaptureException(switch (e.code) {
          'CameraAccessDenied' => CaptureFailure.permissionDenied,
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' =>
            CaptureFailure.permissionDeniedForever,
          _ => CaptureFailure.unavailable,
        }),
      );
    }
  }

  Future<void> _shoot() async {
    if (!_ready || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await _controller.takePicture();
      final bytes = await file.readAsBytes();
      // The camera wrote a temporary file: remove it, the photo lives in memory only.
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      if (mounted) Navigator.of(context).pop(bytes);
    } on CameraException {
      if (mounted) Navigator.of(context).pop(const CaptureException(CaptureFailure.unavailable));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selfie = widget.kind == PhotoKind.selfie;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Fermer',
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    VerificationCopy.captureTitle(widget.kind),
                    style: text.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_ready)
                    CameraPreview(_controller)
                  else
                    const CircularProgressIndicator(color: Colors.white),
                  // The frame shows where the document or the face should be.
                  IgnorePointer(
                    child: FractionallySizedBox(
                      widthFactor: selfie ? 0.7 : 0.9,
                      child: AspectRatio(
                        aspectRatio: selfie ? 0.75 : 1.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(selfie ? 200 : Radii.card),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                children: [
                  Text(
                    selfie ? VerificationCopy.selfieHint : VerificationCopy.photoHint,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: Gaps.md),
                  IconButton.filled(
                    tooltip: VerificationCopy.takePhoto,
                    iconSize: Gaps.xxl,
                    padding: const EdgeInsets.all(Gaps.lg),
                    onPressed: _ready && !_taking ? _shoot : null,
                    icon: const Icon(Icons.camera_alt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
