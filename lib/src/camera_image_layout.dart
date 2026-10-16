import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Describes the supported plane arrangement shared by metadata and import.
YuvPixelFormat validateCameraImageLayout(CameraImage image) {
  if (image.width <= 0 || image.height <= 0) {
    throw FormatException('Camera image dimensions must be positive, got ${image.width}x${image.height}.');
  }
  final group = image.format.group;
  final count = image.planes.length;
  final format = switch ((group, count)) {
    (ImageFormatGroup.bgra8888, 1) => YuvPixelFormat.bgra8888,
    (ImageFormatGroup.yuv420, 2) => YuvPixelFormat.nv12,
    (ImageFormatGroup.yuv420, 3) => YuvPixelFormat.i420,
    _ => throw FormatException('Unsupported camera image layout: $group with $count planes.'),
  };
  final bgra = format == YuvPixelFormat.bgra8888;
  final nv12 = format == YuvPixelFormat.nv12;
  final chromaRows = (image.height + 1) ~/ 2;
  final chromaWidth = (image.width + 1) ~/ 2;
  for (var index = 0; index < count; index++) {
    final source = image.planes[index];
    final rows = bgra || index == 0 ? image.height : chromaRows;
    final width = bgra || index == 0 ? image.width : chromaWidth;
    final pixelStride = bgra
        ? source.bytesPerPixel ?? 4
        : nv12 && index == 1
        ? 2
        : source.bytesPerPixel ?? 1;
    final sampleBytes = bgra
        ? 4
        : nv12 && index == 1
        ? 2
        : 1;
    if (nv12 && index == 1 && source.bytesPerPixel != null && source.bytesPerPixel != 2) {
      throw FormatException('NV12 UV plane pixel stride must be 2, got ${source.bytesPerPixel}.');
    }
    if (pixelStride < sampleBytes) {
      throw FormatException('Camera plane $index pixel stride $pixelStride is smaller than sample size $sampleBytes.');
    }
    final visibleRowBytes = (width - 1) * pixelStride + sampleBytes;
    if (source.bytesPerRow < visibleRowBytes) {
      throw FormatException('Camera plane $index row stride ${source.bytesPerRow} is smaller than visible row size $visibleRowBytes.');
    }
    final requiredLength = (rows - 1) * source.bytesPerRow + visibleRowBytes;
    if (source.bytes.length < requiredLength) {
      throw FormatException('Camera plane $index has ${source.bytes.length} bytes; $requiredLength are required for visible samples.');
    }
  }
  if (format == YuvPixelFormat.i420 &&
      (image.planes[1].bytesPerRow != image.planes[2].bytesPerRow || image.planes[1].bytesPerPixel != image.planes[2].bytesPerPixel)) {
    throw const FormatException('I420 U and V planes must have matching row and pixel strides.');
  }
  return format;
}
