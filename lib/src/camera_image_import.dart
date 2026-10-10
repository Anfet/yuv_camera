import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Imports a camera frame while preserving its declared plane strides.
YuvImage importCameraImage(CameraImage image) {
  final group = image.format.group;
  if (group != ImageFormatGroup.yuv420 && group != ImageFormatGroup.bgra8888) {
    throw FormatException('Unsupported camera image format: $group');
  }
  final bgra = group == ImageFormatGroup.bgra8888;
  final chromaRows = (image.height + 1) ~/ 2;
  final planes = <YuvPlane>[];
  for (var index = 0; index < image.planes.length; index++) {
    final source = image.planes[index];
    final rows = bgra || index == 0 ? image.height : chromaRows;
    final pixelStride = bgra ? 4 : source.bytesPerPixel ?? 1;
    final bytes = Uint8List(rows * source.bytesPerRow);
    bytes.setRange(0, source.bytes.length.clamp(0, bytes.length), source.bytes);
    planes.add(YuvPlane(rows, source.bytesPerRow, pixelStride, bytes));
  }
  return bgra
      ? YuvImage.bgra(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve)
      : YuvImage.i420(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve);
}
