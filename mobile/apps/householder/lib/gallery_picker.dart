import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

/// Longest side of an uploaded screenshot, in pixels: legible, and light on mobile data.
const int _maxSide = 1600;
const int _jpegQuality = 80;

/// Any image (a screenshot is usually a PNG) as a resized JPEG, which is all the server accepts.
/// Null when the bytes are not an image.
Uint8List? toJpeg(Uint8List original) {
  if (original.isEmpty) return null;
  final decoded = img.decodeImage(original);
  if (decoded == null) return null;
  var image = decoded;
  if (image.width > _maxSide || image.height > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide)
        : img.copyResize(image, height: _maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
}

/// Picks the receipt screenshot from the gallery. This is the only place in the apps where a
/// picture can come from the gallery: the identity photos are taken live, never picked.
class GalleryProofPicker implements ProofPicker {
  @override
  Future<CapturedPhoto?> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await compute(toJpeg, await file.readAsBytes());
    if (bytes == null) throw const FormatException('not an image');
    return CapturedPhoto(bytes: bytes, capturedAt: DateTime.now());
  }
}
