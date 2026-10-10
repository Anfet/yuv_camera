import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/ext.dart';

/// `YuvImageToCameraExt.toInputImage()` passes `google_mlkit_commons`
/// 0.11.0's Android byte-array path real NV21 bytes (`Y` then interleaved
/// **V, U** chroma) -- the only semi-planar layout it recognizes -- rather
/// than this package's UV-ordered `nv12` storage or three separate I420
/// planes mislabelled as `yuv420` (iOS-only in that enum, despite the name;
/// see its own doc comments). iOS gets a packed BGRA buffer right-padded to a width multiple of 4.
///
/// Every case below builds its source planes with real row padding **and** a
/// real per-sample pixel gap (`pixelStride > sampleBytes`, `layout:
/// YuvPlaneLayout.preserve`), so a fix that only works on already-tight or
/// merely row-padded input would not be caught. The gap bytes are filled with
/// a sentinel that never matches a visible sample, so a test that accidentally
/// reads a gap byte instead of the next visible sample fails loudly.
void main() {
  const gapSentinel = 0xEE;

  int deterministicByte(int seed, int index) => (index * 37 + seed) & 0xff;

  /// Builds a plane with [rowPadding] trailing bytes per row and, when
  /// [pixelStride] exceeds [sampleBytes], a real inter-sample gap: every
  /// sample slot holds [sampleBytes] visible bytes followed by
  /// `pixelStride - sampleBytes` gap bytes, both filled with [gapSentinel].
  YuvPlane paddedPlane({
    required int rows,
    required int columns,
    required int pixelStride,
    required int sampleBytes,
    required int rowPadding,
    required int seed,
  }) {
    final rowStride = columns * pixelStride + rowPadding;
    final bytes = Uint8List(rows * rowStride)..fillRange(0, rows * rowStride, gapSentinel);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        for (var b = 0; b < sampleBytes; b++) {
          bytes[row * rowStride + col * pixelStride + b] = deterministicByte(seed + b, row * columns + col);
        }
      }
    }
    return YuvPlane(rows, rowStride, pixelStride, bytes);
  }

  test('I420 with padded, pixel-gapped planes produces true NV21 (Y then V,U) bytes', () {
    const width = 6;
    const height = 4;
    const chromaWidth = 3;
    const chromaHeight = 2;

    final yPlane = paddedPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, rowPadding: 5, seed: 1);
    // Real pixel gap: one visible byte per sample, one gap byte -- the
    // interleaved-chroma-exposed-as-two-planes layout some Android devices
    // report for I420.
    final uPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, rowPadding: 4, seed: 100);
    final vPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, rowPadding: 4, seed: 200);

    final image = YuvImage.i420(width, height, planes: [yPlane, uPlane, vPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.nv21);
    expect(inputImage.metadata!.size, const Size(6, 4));
    expect(inputImage.metadata!.rotation, InputImageRotation.rotation0deg);
    expect(inputImage.metadata!.bytesPerRow, width);

    final bytes = inputImage.bytes!;
    expect(bytes.length, width * height + chromaWidth * chromaHeight * 2);
    expect(bytes, isNot(contains(gapSentinel)), reason: 'no gap/padding byte from the source planes may leak into the output');

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        expect(bytes[row * width + col], deterministicByte(1, row * width + col), reason: 'Y[$row,$col]');
      }
    }

    final chromaStart = width * height;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final i = row * chromaWidth + col;
        expect(bytes[chromaStart + i * 2], deterministicByte(200, i), reason: 'V[$row,$col] must come first (NV21)');
        expect(bytes[chromaStart + i * 2 + 1], deterministicByte(100, i), reason: 'U[$row,$col] must come second (NV21)');
      }
    }
  });

  test('NV12 (UV-ordered) with padded, pixel-gapped chroma is swapped to true NV21 (VU) bytes', () {
    const width = 6;
    const height = 4;
    const chromaWidth = 3;
    const chromaHeight = 2;

    final yPlane = paddedPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, rowPadding: 5, seed: 1);
    // Real pixel gap on top of the interleaved UV pair: 2 visible bytes (U
    // then V, deterministicByte's `seed + b` for b in 0..1) followed by 2 gap
    // bytes per sample slot, i.e. `pixelStride (4) > sampleBytes (2)`.
    final uvPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 4, sampleBytes: 2, rowPadding: 6, seed: 100);

    final image = YuvImage.nv12(width, height, planes: [yPlane, uvPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.nv21);
    expect(inputImage.metadata!.size, const Size(6, 4));
    expect(inputImage.metadata!.rotation, InputImageRotation.rotation0deg);
    expect(inputImage.metadata!.bytesPerRow, width);

    final bytes = inputImage.bytes!;
    expect(bytes.length, width * height + chromaWidth * chromaHeight * 2);
    expect(bytes, isNot(contains(gapSentinel)), reason: 'no gap/padding byte from the source planes may leak into the output');

    final chromaStart = width * height;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final i = row * chromaWidth + col;
        final sourceU = deterministicByte(100, i);
        final sourceV = deterministicByte(101, i);
        expect(bytes[chromaStart + i * 2], sourceV, reason: 'V[$row,$col] must be written first (NV21)');
        expect(bytes[chromaStart + i * 2 + 1], sourceU, reason: 'U[$row,$col] must be written second (NV21)');
      }
    }
  });

  test('BGRA with a padded, pixel-gapped plane is right-padded to a width multiple of 4 with transparent pixels', () {
    const width = 5;
    const paddedWidth = 8;
    const height = 3;
    // Real pixel gap: 4 visible BGRA bytes followed by 2 gap bytes per pixel
    // slot, i.e. `pixelStride (6) > sampleBytes (4)`.
    final bgraPlane = paddedPlane(rows: height, columns: width, pixelStride: 6, sampleBytes: 4, rowPadding: 8, seed: 1);

    final image = YuvImage.bgra(width, height, planes: [bgraPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.bgra8888);
    expect(inputImage.metadata!.size, const Size(8, 3));
    expect(inputImage.metadata!.rotation, InputImageRotation.rotation0deg);
    expect(inputImage.metadata!.bytesPerRow, paddedWidth * 4);
    expect(image.width, width, reason: 'the source image must not change');

    final bytes = inputImage.bytes!;
    expect(bytes.length, paddedWidth * height * 4);
    expect(bytes, isNot(contains(gapSentinel)), reason: 'no gap/padding byte from the source plane may leak into the output');

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < paddedWidth; col++) {
        for (var b = 0; b < 4; b++) {
          final expected = col < width ? deterministicByte(1 + b, row * width + col) : 0;
          expect(bytes[row * paddedWidth * 4 + col * 4 + b], expected, reason: 'BGRA[$row,$col,$b]');
        }
      }
    }
  });

  test('BGRA whose width is a multiple of 4 keeps its tight buffer and size', () {
    const width = 4;
    const height = 2;
    final bgraPlane = paddedPlane(rows: height, columns: width, pixelStride: 4, sampleBytes: 4, rowPadding: 8, seed: 1);

    final inputImage = YuvImage.bgra(width, height, planes: [bgraPlane], layout: YuvPlaneLayout.preserve).toInputImage();

    expect(inputImage.metadata!.size, const Size(4, 2));
    expect(inputImage.metadata!.bytesPerRow, width * 4);
    expect(inputImage.bytes!.length, width * height * 4);
  });
}
