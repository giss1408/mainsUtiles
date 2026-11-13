import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo/gallery_picker.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a PNG screenshot becomes a JPEG', () {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 20)));
    final out = toJpeg(png)!;
    expect(out.sublist(0, 3), [0xff, 0xd8, 0xff]);
    final back = img.decodeJpg(out)!;
    expect((back.width, back.height), (40, 20));
  });

  test('a JPEG stays a JPEG', () {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 30, height: 30)));
    expect(toJpeg(jpeg)!.sublist(0, 3), [0xff, 0xd8, 0xff]);
  });

  test('a large screenshot is brought down to 1600 pixels on its long side', () {
    final big = Uint8List.fromList(img.encodePng(img.Image(width: 3200, height: 1000)));
    final back = img.decodeJpg(toJpeg(big)!)!;
    expect((back.width, back.height), (1600, 500));
  });

  test('something that is not an image gives nothing', () {
    expect(toJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(toJpeg(Uint8List(0)), isNull);
  });
}
