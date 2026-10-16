import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_layout.dart';

/// Imports a camera frame while preserving its declared plane strides.
YuvImage importCameraImage(CameraImage image) {
  final format = validateCameraImageLayout(image);
  final bgra = format == YuvPixelFormat.bgra8888;
  final nv12 = format == YuvPixelFormat.nv12;
  final chromaRows = (image.height + 1) ~/ 2;
  final planes = <YuvPlane>[];
  for (var index = 0; index < image.planes.length; index++) {
    final source = image.planes[index];
    final rows = bgra || index == 0 ? image.height : chromaRows;
    final pixelStride = bgra
        ? source.bytesPerPixel ?? 4
        : nv12 && index == 1
        ? 2
        : source.bytesPerPixel ?? 1;
    final bytes = Uint8List(rows * source.bytesPerRow);
    bytes.setRange(0, source.bytes.length.clamp(0, bytes.length), source.bytes);
    planes.add(YuvPlane(rows, source.bytesPerRow, pixelStride, bytes));
  }
  return switch (format) {
    YuvPixelFormat.bgra8888 => YuvImage.bgra(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve),
    YuvPixelFormat.nv12 => YuvImage.nv12(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve),
    YuvPixelFormat.i420 => YuvImage.i420(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve),
  };
}
