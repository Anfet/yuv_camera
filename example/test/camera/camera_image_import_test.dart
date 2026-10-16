import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

void main() {
  setUpAll(YuvFfi.initialize);

  test('imports a padded two-plane iOS NV12 image with odd dimensions and null pixel strides', () {
    final cameraImage = _nv12CameraImage();

    final imported = importCameraImage(cameraImage);
    expect(imported.format, YuvPixelFormat.nv12);
    expect(imported.yPlane.rowStride, 4);
    expect(imported.yPlane.pixelStride, 1);
    expect(imported.uPlane.rowStride, 5);
    expect(imported.uPlane.pixelStride, 2);
    expect(imported.uPlane.bytes, [90, 240, 54, 34, 0xee, 90, 240, 54, 34, 0]);
    expect(imported.toBgraBytes().take(4), [0, 1, 255, 255]);
  });

  test('preserves pixel-stride-2 chroma planes', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [
      CameraImagePlane(bytes: Uint8List.fromList(List<int>.filled(16, 82)), bytesPerRow: 4, bytesPerPixel: 1, width: 4, height: 4),
      CameraImagePlane(bytes: Uint8List.fromList([90, 0, 90, 0, 90, 0, 90, 0]), bytesPerRow: 4, bytesPerPixel: 2, width: 2, height: 2),
      CameraImagePlane(bytes: Uint8List.fromList([240, 0, 240, 0, 240, 0, 240, 0]), bytesPerRow: 4, bytesPerPixel: 2, width: 2, height: 2),
    ]);
    final imported = importCameraImage(image);
    expect(imported.format, YuvPixelFormat.i420);
    expect(imported.uPlane.pixelStride, 2);
    expect(imported.vPlane.pixelStride, 2);
    expect(imported.planes.map((plane) => plane.rowStride), [4, 4, 4]);
    expect(imported.toBgraBytes().take(4), [0, 1, 255, 255]);
  });

  test('zero-fills only truncated final row padding', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(6, 4, 1, 22), _plane(6, 2, 2, 10), _plane(6, 2, 2, 10)]);
    final imported = importCameraImage(image);
    expect(imported.yPlane.bytes.sublist(22), [0, 0]);
    expect(imported.uPlane.bytes.sublist(10), [0, 0]);
  });

  test('rejects layouts missing visible samples or with an unsupported plane count', () {
    final malformed = <CameraImage>[
      _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 2, 5)]),
      _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 1, 8)]),
      _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 2, 8), _plane(4, 2, 2, 8), _plane(4, 2, 1, 8)]),
      _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 2, 8), _plane(6, 2, 2, 12)]),
    ];
    for (final image in malformed) {
      expect(() => importCameraImage(image), throwsFormatException);
    }
  });

  test('imports padded BGRA without repacking', () {
    final image = _cameraImage(ImageFormatGroup.bgra8888, 2, 2, [_plane(12, 2, 4, 24)]);
    final imported = importCameraImage(image);
    expect(imported.format, YuvPixelFormat.bgra8888);
    expect(imported.yPlane.rowStride, 12);
    expect(imported.yPlane.pixelStride, 4);
    expect(imported.toBgraBytes().take(4), [1, 2, 3, 4]);
  });

  test('preserves BGRA pixel gaps and a short final row', () {
    final image = _cameraImage(ImageFormatGroup.bgra8888, 2, 2, [
      CameraImagePlane(
        bytes: Uint8List.fromList([
          1,
          2,
          3,
          4,
          0xee,
          0xee,
          0xee,
          0xee,
          5,
          6,
          7,
          8,
          0xee,
          0xee,
          0xee,
          0xee,
          9,
          10,
          11,
          12,
          0xee,
          0xee,
          0xee,
          0xee,
          13,
          14,
          15,
          16,
        ]),
        bytesPerRow: 16,
        bytesPerPixel: 8,
        width: 2,
        height: 2,
      ),
    ]);
    final imported = importCameraImage(image);

    expect(imported.yPlane.rowStride, 16);
    expect(imported.yPlane.pixelStride, 8);
    expect(imported.yPlane.bytes, [
      1,
      2,
      3,
      4,
      0xee,
      0xee,
      0xee,
      0xee,
      5,
      6,
      7,
      8,
      0xee,
      0xee,
      0xee,
      0xee,
      9,
      10,
      11,
      12,
      0xee,
      0xee,
      0xee,
      0xee,
      13,
      14,
      15,
      16,
      0,
      0,
      0,
      0,
    ]);
    expect(imported.toBgraBytes(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
  });

  test('defaults a null BGRA pixel stride to four and rejects malformed strides or spans', () {
    final nullStride = _cameraImage(ImageFormatGroup.bgra8888, 1, 1, [
      CameraImagePlane(bytes: Uint8List.fromList([1, 2, 3, 4]), bytesPerRow: 4, bytesPerPixel: null, width: 1, height: 1),
    ]);
    expect(importCameraImage(nullStride).yPlane.pixelStride, 4);

    for (final pixelStride in [-1, 0, 1, 2, 3]) {
      final malformed = _cameraImage(ImageFormatGroup.bgra8888, 1, 1, [
        CameraImagePlane(bytes: Uint8List.fromList([1, 2, 3, 4]), bytesPerRow: 4, bytesPerPixel: pixelStride, width: 1, height: 1),
      ]);
      expect(() => importCameraImage(malformed), throwsFormatException);
    }
    final shortRow = _cameraImage(ImageFormatGroup.bgra8888, 2, 1, [
      CameraImagePlane(bytes: Uint8List.fromList(List<int>.filled(12, 0)), bytesPerRow: 11, bytesPerPixel: 8, width: 2, height: 1),
    ]);
    final shortBuffer = _cameraImage(ImageFormatGroup.bgra8888, 2, 1, [
      CameraImagePlane(bytes: Uint8List.fromList(List<int>.filled(11, 0)), bytesPerRow: 12, bytesPerPixel: 8, width: 2, height: 1),
    ]);
    expect(() => importCameraImage(shortRow), throwsFormatException);
    expect(() => importCameraImage(shortBuffer), throwsFormatException);
  });

  test('rejects formats the source never requests', () {
    for (final group in <ImageFormatGroup>[ImageFormatGroup.nv21, ImageFormatGroup.jpeg, ImageFormatGroup.unknown]) {
      expect(() => importCameraImage(_cameraImage(group, 2, 2, [_plane(2, 2, 1, 4)])), throwsFormatException);
    }
  });
}

CameraImage _cameraImage(ImageFormatGroup group, int width, int height, List<CameraImagePlane> planes) => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: CameraImageFormat(group, raw: group.name),
    width: width,
    height: height,
    planes: planes,
  ),
);

CameraImage _nv12CameraImage() => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 875704438),
    width: 3,
    height: 3,
    planes: [
      CameraImagePlane(
        bytes: Uint8List.fromList([82, 82, 82, 0xee, 82, 82, 82, 0xee, 82, 82, 82]),
        bytesPerRow: 4,
        bytesPerPixel: null,
        width: 3,
        height: 3,
      ),
      CameraImagePlane(bytes: Uint8List.fromList([90, 240, 54, 34, 0xee, 90, 240, 54, 34]), bytesPerRow: 5, bytesPerPixel: null, width: 2, height: 2),
    ],
  ),
);

CameraImagePlane _plane(int rowStride, int height, int pixelStride, int length) => CameraImagePlane(
  bytes: Uint8List.fromList(List<int>.generate(length, (index) => index + 1)),
  bytesPerRow: rowStride,
  bytesPerPixel: pixelStride,
  width: rowStride ~/ pixelStride,
  height: height,
);
