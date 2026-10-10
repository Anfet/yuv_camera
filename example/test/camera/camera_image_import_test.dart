import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

void main() {
  test('preserves pixel-stride-2 chroma planes', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 2, 8), _plane(4, 2, 2, 8)]);
    final imported = importCameraImage(image);
    expect(imported.uPlane.pixelStride, 2);
    expect(imported.planes.map((plane) => plane.rowStride), [4, 4, 4]);
    expect(imported.uPlane.bytes, List<int>.generate(8, (index) => index + 1));
  });

  test('zero-fills a truncated camera plane', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 14), _plane(4, 2, 2, 7), _plane(4, 2, 2, 8)]);
    final imported = importCameraImage(image);
    expect(imported.yPlane.bytes.sublist(14), [0, 0]);
    expect(imported.uPlane.bytes.last, 0);
  });

  test('imports padded BGRA without repacking', () {
    final image = _cameraImage(ImageFormatGroup.bgra8888, 2, 2, [_plane(12, 2, 4, 24)]);
    final imported = importCameraImage(image);
    expect(imported.format, YuvPixelFormat.bgra8888);
    expect(imported.yPlane.rowStride, 12);
    expect(imported.yPlane.pixelStride, 4);
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

CameraImagePlane _plane(int rowStride, int height, int pixelStride, int length) => CameraImagePlane(
  bytes: Uint8List.fromList(List<int>.generate(length, (index) => index + 1)),
  bytesPerRow: rowStride,
  bytesPerPixel: pixelStride,
  width: rowStride ~/ pixelStride,
  height: height,
);
