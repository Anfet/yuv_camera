import 'dart:typed_data';
import 'dart:ui';

import 'package:yuv_ffi/yuv_ffi.dart';

import 'yuv_crop_target.dart';

/// The outline kept by [YuvImage.croppedToShape] inside the cropped rectangle.
enum YuvCropShape {
  /// The whole rectangle. A square rectangle comes from a [YuvCropTarget.square] target.
  rectangle,

  /// The ellipse inscribed in the rectangle. A circle comes from a [YuvCropTarget.square] target.
  ellipse;

  bool _contains(int x, int y, int width, int height) {
    if (this == rectangle) {
      return true;
    }
    // With dx = (2x + 1 - width) / width and dy = (2y + 1 - height) / height, `dx² + dy² <= 1` in exact integers.
    final dx = 2 * x + 1 - width;
    final dy = 2 * y + 1 - height;
    return dx * dx * height * height + dy * dy * width * width <= width * width * height * height;
  }
}

/// A rectangle cut out of a [YuvImage] together with the [shape] that remains visible in it.
///
/// Points outside the shape are painted with [fill] in [image] and are fully transparent in [toBgraBytes], so
/// transparency follows the shape, not a key color. Create it with [YuvShapeCrop.croppedToShape].
final class YuvShapedImage {
  YuvShapedImage._(this.image, this.shape, this.region, this.fill, this.insideCount);

  /// The cut-out rectangle in the format of the source, an independent copy of it. Points outside the [shape] hold [fill].
  final YuvImage image;

  /// The outline that remains visible in [image].
  final YuvCropShape shape;

  /// Where [image] was cut from, in pixels of the source.
  final Rect region;

  /// The color painted outside the [shape]; its alpha is ignored.
  final Color fill;

  /// How many points of [image] are inside the [shape].
  final int insideCount;

  /// Whether the point `(x, y)` of [image] is inside the [shape]. A point outside [image] is not.
  bool contains(int x, int y) {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
      return false;
    }
    return shape._contains(x, y, image.width, image.height);
  }

  /// Returns exactly `width * height * 4` tightly packed BGRA bytes of [image] where points outside the [shape] have alpha 0.
  ///
  /// Every call returns a new buffer with the same content.
  Uint8List toBgraBytes() {
    final bytes = image.toBgraBytes();
    if (shape == YuvCropShape.rectangle) {
      return bytes;
    }
    final width = image.width;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < width; x++) {
        if (!contains(x, y)) {
          bytes[(y * width + x) * 4 + 3] = 0;
        }
      }
    }
    return bytes;
  }
}

/// Cutting a shape out of a [YuvImage].
extension YuvShapeCrop on YuvImage {
  /// Cuts the rectangle that [target] places in this image and keeps only [shape] of it.
  ///
  /// Points outside the [shape] are painted with [fill] (its alpha is ignored) and become transparent in
  /// [YuvShapedImage.toBgraBytes]. Points inside never change. For I420 and NV12 a chroma sample is painted only
  /// when all the points it covers (up to 2x2) are outside the shape; otherwise it keeps the color of the image.
  ///
  /// This image is left unchanged. Needs a `YuvFfi.initialize()` that has completed, like any other crop. Throws an
  /// [ArgumentError] when [target] is invalid for this image (see [YuvCropTarget.place]).
  YuvShapedImage croppedToShape(YuvCropTarget target, {YuvCropShape shape = YuvCropShape.rectangle, Color fill = const Color(0xFF000000)}) {
    final region = target.place(size);
    final image = cropped(region);
    final width = image.width;
    final height = image.height;
    var insideCount = width * height;
    if (shape != YuvCropShape.rectangle) {
      insideCount = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (shape._contains(x, y, width, height)) {
            insideCount++;
          }
        }
      }
      _paintOutside(image, shape, fill);
    }
    return YuvShapedImage._(image, shape, region, fill, insideCount);
  }
}

void _paintOutside(YuvImage image, YuvCropShape shape, Color fill) {
  final width = image.width;
  final height = image.height;
  bool outside(int x, int y) => !shape._contains(x, y, width, height);
  final argb = fill.toARGB32();
  final red = (argb >> 16) & 0xFF;
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;

  if (image.format == YuvPixelFormat.bgra8888) {
    final plane = image.yPlane;
    final bytes = plane.bytes;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (outside(x, y)) {
          final offset = y * plane.rowStride + x * plane.pixelStride;
          bytes[offset] = blue;
          bytes[offset + 1] = green;
          bytes[offset + 2] = red;
          bytes[offset + 3] = 0xFF;
        }
      }
    }
    image.markDirty();
    return;
  }

  // The color is converted by the same backend as every other image: a 2x2 fill gives one Y per point and one U/V pair.
  final swatch = YuvImage.fromRgbaBytes(
    Uint8List.fromList([
      for (int i = 0; i < 4; i++) ...[red, green, blue, 0xFF],
    ]),
    width: 2,
    height: 2,
    format: YuvPixelFormat.i420,
  );
  final fillY = swatch.yPlane.bytes[0];
  final fillU = swatch.uPlane.bytes[0];
  final fillV = swatch.vPlane.bytes[0];

  final luma = image.yPlane;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if (outside(x, y)) {
        luma.bytes[y * luma.rowStride + x * luma.pixelStride] = fillY;
      }
    }
  }

  final isI420 = image.format == YuvPixelFormat.i420;
  final uPlane = image.uPlane;
  final vPlane = isI420 ? image.vPlane : uPlane;
  for (int cy = 0; cy < (height + 1) ~/ 2; cy++) {
    for (int cx = 0; cx < (width + 1) ~/ 2; cx++) {
      if (_coveredPoints(cx, cy, width, height).every((point) => outside(point.$1, point.$2))) {
        final uOffset = cy * uPlane.rowStride + cx * uPlane.pixelStride;
        uPlane.bytes[uOffset] = fillU;
        // NV12 keeps V right after U in the same interleaved plane.
        final vOffset = isI420 ? cy * vPlane.rowStride + cx * vPlane.pixelStride : uOffset + 1;
        vPlane.bytes[vOffset] = fillV;
      }
    }
  }
  image.markDirty();
}

Iterable<(int, int)> _coveredPoints(int cx, int cy, int width, int height) sync* {
  for (int y = 2 * cy; y < 2 * cy + 2 && y < height; y++) {
    for (int x = 2 * cx; x < 2 * cx + 2 && x < width; x++) {
      yield (x, y);
    }
  }
}
