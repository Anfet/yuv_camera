import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const _ellipse8x8 = ['..####..', '.######.', '########', '########', '########', '########', '.######.', '..####..'];
const _ellipse9x7 = ['..#####..', '.#######.', '#########', '#########', '#########', '.#######.', '..#####..'];
const _magenta = Color(0xFFFF00FF);
const _target = YuvCropTarget.pixels(Size(9, 7), alignment: Alignment.topLeft, offset: Offset(1, 1));

/// Shape crop on the real backend of the platform (native library, WASM or JS), without a camera.
///
/// The expected numbers are the reference values of the VM test `example/test/camera/yuv_shape_crop_test.dart`:
/// the inside mask of a 9x7 ellipse, the 2x2 chroma blocks of an odd-origin crop and the pixel counts of the shapes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(YuvFfi.initialize);

  for (final format in [YuvPixelFormat.i420, YuvPixelFormat.nv12, YuvPixelFormat.bgra8888]) {
    group(format.name, () {
      testWidgets('ellipse keeps the inside, fills the outside and leaves the source alone', (tester) async {
        final source = _source(format, 11, 9);
        final before = source.toBytes();
        final region = _target.place(source.size);
        final plain = source.cropped(region);
        final plainBgra = plain.toBgraBytes();
        final shaped = source.croppedToShape(_target, shape: YuvCropShape.ellipse, fill: _magenta);

        // (a) the result describes the crop and keeps the source format.
        expect(shaped.region, region);
        expect(shaped.fill, _magenta);
        expect(shaped.image.format, format);
        final bgra = shaped.toBgraBytes();
        expect(bgra.length, 9 * 7 * 4);

        // (b) inside points equal the plain crop, outside points are transparent and filled in the source format.
        final swatch = _source(format, 2, 2, rgba: [255, 0, 255, 255]);
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
                expect(_luma(shaped.image, x, y), _luma(swatch, 0, 0), reason: 'Y outside ($x, $y)');
              }
            }
          }
        }
        expect(shaped.toBgraBytes(), bgra);

        // (c) 4:2:0 formats: only the 2x2 chroma blocks fully outside the ellipse take the fill chroma.
        if (format != YuvPixelFormat.bgra8888) {
          const filled = {(0, 3), (4, 0), (4, 3)};
          final fillChroma = _chroma(swatch, 0, 0);
          for (int cy = 0; cy < 4; cy++) {
            for (int cx = 0; cx < 5; cx++) {
              expect(_chroma(shaped.image, cx, cy), filled.contains((cx, cy)) ? fillChroma : _chroma(plain, cx, cy), reason: 'chroma ($cx, $cy)');
            }
          }
        }

        // (d) the source is neither changed by the crop nor shares memory with the result.
        expect(source.toBytes(), before);
        shaped.image.yPlane.bytes[0] ^= 0xFF;
        expect(source.toBytes(), before);
      });

      testWidgets('rectangle equals the plain crop and is fully opaque', (tester) async {
        final source = _source(format, 11, 9);
        final shaped = source.croppedToShape(_target, fill: _magenta);
        final bgra = shaped.toBgraBytes();
        expect(bgra, source.cropped(shaped.region).toBgraBytes());
        expect([for (int i = 3; i < bgra.length; i += 4) bgra[i]].every((alpha) => alpha == 255), true);
        expect(shaped.insideCount, 9 * 7);
      });

      testWidgets('ellipse mask matches the 8x8 and 9x7 references', (tester) async {
        for (final (reference, count) in [(_ellipse8x8, 52), (_ellipse9x7, 51)]) {
          final width = reference.first.length;
          final height = reference.length;
          final shaped = _source(
            format,
            width,
            height,
          ).croppedToShape(YuvCropTarget.pixels(Size(width.toDouble(), height.toDouble())), shape: YuvCropShape.ellipse);
          for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
              expect(shaped.contains(x, y), reference[y][x] == '#', reason: '${width}x$height at ($x, $y)');
            }
          }
          expect(shaped.contains(-1, 0) || shaped.contains(0, -1) || shaped.contains(width, 0) || shaped.contains(0, height), false);
          expect(shaped.insideCount, count, reason: '${width}x$height');
        }
      });

      testWidgets('ellipse covers 101780 points of a square(.5) crop of 720x960', (tester) async {
        final shaped = _source(format, 720, 960).croppedToShape(const YuvCropTarget.square(.5), shape: YuvCropShape.ellipse);
        expect(shaped.region.size, const Size(360, 360));
        expect(shaped.insideCount, 101780);
      });

      testWidgets('ellipse covers 95424 points of a pixels(300x405) crop of 720x960', (tester) async {
        final shaped = _source(format, 720, 960).croppedToShape(const YuvCropTarget.pixels(Size(300, 405)), shape: YuvCropShape.ellipse);
        expect(shaped.region.size, const Size(300, 405));
        expect(shaped.insideCount, 95424);
      });
    });
  }
}

/// A deterministic gradient, or one flat [rgba] colour.
YuvImage _source(YuvPixelFormat format, int width, int height, {List<int>? rgba}) => YuvImage.fromRgbaBytes(
  Uint8List.fromList([
    for (int y = 0; y < height; y++)
      for (int x = 0; x < width; x++) ...(rgba ?? [(x * 23) & 0xFF, (y * 28) & 0xFF, ((x + y) * 11) & 0xFF, 255]),
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
