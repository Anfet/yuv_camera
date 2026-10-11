import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const _ellipse8x8 = ['..####..', '.######.', '########', '########', '########', '########', '.######.', '..####..'];
const _ellipse9x7 = ['..#####..', '.#######.', '#########', '#########', '#########', '.#######.', '..#####..'];
const _magenta = Color(0xFFFF00FF);
const _target = YuvCropTarget.pixels(Size(9, 7), alignment: Alignment.topLeft, offset: Offset(1, 1));

void main() {
  setUpAll(YuvFfi.initialize);

  YuvShapedImage ellipse(YuvImage source, {Color fill = _magenta}) => source.croppedToShape(_target, shape: YuvCropShape.ellipse, fill: fill);

  test('ellipse mask matches the reference and counts', () {
    for (final reference in [_ellipse8x8, _ellipse9x7]) {
      final width = reference.first.length;
      final height = reference.length;
      final shaped = _source(
        YuvPixelFormat.i420,
        width,
        height,
      ).croppedToShape(YuvCropTarget.pixels(Size(width.toDouble(), height.toDouble())), shape: YuvCropShape.ellipse);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(shaped.contains(x, y), reference[y][x] == '#', reason: '${width}x$height at ($x, $y)');
        }
      }
      expect(shaped.contains(-1, 0) || shaped.contains(0, -1) || shaped.contains(width, 0) || shaped.contains(0, height), false);
    }
    const counts = {(1, 1): 1, (2, 2): 4, (3, 3): 9, (360, 360): 101780, (300, 405): 95424, (8, 8): 52, (9, 7): 51};
    counts.forEach((size, count) {
      final shaped = _source(
        YuvPixelFormat.i420,
        size.$1,
        size.$2,
      ).croppedToShape(YuvCropTarget.pixels(Size(size.$1.toDouble(), size.$2.toDouble())), shape: YuvCropShape.ellipse);
      expect(shaped.insideCount, count, reason: '${size.$1}x${size.$2}');
    });
  });

  for (final format in YuvPixelFormat.values) {
    test('${format.name} ellipse keeps the inside, fills the outside and leaves the source alone', () {
      final source = _source(format, 11, 9);
      final before = source.toBytes();
      final region = _target.place(source.size);
      final plain = source.cropped(region);
      final plainBgra = plain.toBgraBytes();
      final shaped = ellipse(source);

      expect(shaped.region, region);
      expect(shaped.fill, _magenta);
      expect(shaped.image.format, format);
      final bgra = shaped.toBgraBytes();
      expect(bgra.length, 9 * 7 * 4);
      final fillY = YuvImage.fromRgbaBytes(
        Uint8List.fromList([
          for (int i = 0; i < 4; i++) ...[255, 0, 255, 255],
        ]),
        width: 2,
        height: 2,
        format: YuvPixelFormat.i420,
      ).yPlane.bytes[0];
      for (int y = 0; y < 7; y++) {
        for (int x = 0; x < 9; x++) {
          final offset = (y * 9 + x) * 4;
          if (shaped.contains(x, y)) {
            expect(bgra.sublist(offset, offset + 4), plainBgra.sublist(offset, offset + 4), reason: 'inside ($x, $y)');
          } else {
            expect(bgra[offset + 3], 0, reason: 'alpha outside ($x, $y)');
            if (format == YuvPixelFormat.bgra8888) {
              expect(_pixel(shaped.image, x, y), [255, 0, 255, 255], reason: 'fill outside ($x, $y)');
            } else {
              expect(_luma(shaped.image, x, y), fillY, reason: 'Y outside ($x, $y)');
            }
          }
        }
      }
      expect(bgra, shaped.toBgraBytes());

      if (format != YuvPixelFormat.bgra8888) {
        final filled = {(0, 3), (4, 0), (4, 3)};
        final fillChroma = _chroma(shaped.image, 0, 3);
        for (int cy = 0; cy < 4; cy++) {
          for (int cx = 0; cx < 5; cx++) {
            expect(_chroma(shaped.image, cx, cy), filled.contains((cx, cy)) ? fillChroma : _chroma(plain, cx, cy), reason: 'chroma ($cx, $cy)');
          }
        }
      }

      expect(source.toBytes(), before);
      shaped.image.yPlane.bytes[0] ^= 0xFF;
      expect(source.toBytes(), before);
    });
  }

  test('rectangle equals the plain crop and is fully opaque', () {
    for (final format in YuvPixelFormat.values) {
      final source = _source(format, 11, 9);
      final shaped = source.croppedToShape(_target, fill: _magenta);
      final bgra = shaped.toBgraBytes();
      expect(bgra, source.cropped(shaped.region).toBgraBytes(), reason: format.name);
      expect([for (int i = 3; i < bgra.length; i += 4) bgra[i]].every((alpha) => alpha == 255), true, reason: format.name);
      expect(shaped.insideCount, 9 * 7, reason: format.name);
    }
  });

  test('default fill is black', () {
    final shaped = _source(YuvPixelFormat.bgra8888, 11, 9).croppedToShape(_target, shape: YuvCropShape.ellipse);
    expect(_pixel(shaped.image, 0, 0), [0, 0, 0, 255]);
  });
}

YuvImage _source(YuvPixelFormat format, int width, int height) => YuvImage.fromRgbaBytes(
  Uint8List.fromList([
    for (int y = 0; y < height; y++)
      for (int x = 0; x < width; x++) ...[(x * 23) & 0xFF, (y * 28) & 0xFF, ((x + y) * 11) & 0xFF, 255],
  ]),
  width: width,
  height: height,
  format: format,
);

List<int> _pixel(YuvImage image, int x, int y) {
  final plane = image.yPlane;
  final offset = y * plane.rowStride + x * plane.pixelStride;
  return plane.bytes.sublist(offset, offset + 4);
}

int _luma(YuvImage image, int x, int y) => image.yPlane.bytes[y * image.yPlane.rowStride + x * image.yPlane.pixelStride];

List<int> _chroma(YuvImage image, int cx, int cy) {
  final u = image.uPlane;
  final uOffset = cy * u.rowStride + cx * u.pixelStride;
  if (image.format == YuvPixelFormat.nv12) {
    return [u.bytes[uOffset], u.bytes[uOffset + 1]];
  }
  final v = image.vPlane;
  return [u.bytes[uOffset], v.bytes[cy * v.rowStride + cx * v.pixelStride]];
}
