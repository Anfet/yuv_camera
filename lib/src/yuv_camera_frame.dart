// Keep the established public `load` constructor argument while storing it privately.
// ignore_for_file: prefer_initializing_formals

import 'package:yuv_ffi/yuv_ffi.dart';

/// One immutable camera delivery with lazily imported image representations.
///
/// [image] and [upright] are owned by this frame and must not be mutated. Use
/// `copy()` before applying an in-place operation. iOS behavior was verified
/// with the front camera on one iPhone running iOS 18.7 in portrait and
/// landscape; this observation is limited to that configuration.
class YuvCameraFrame {
  /// Creates a delivery whose raw image is produced at most once by [load].
  YuvCameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.orientation,
    required this.timestamp,
    required YuvImage Function() load,
  }) : _load = load;

  final int width;
  final int height;
  final YuvPixelFormat format;
  final YuvFrameOrientation orientation;
  final Duration timestamp;
  final YuvImage Function() _load;
  YuvImage? _image;
  YuvImage? _upright;

  /// Raw camera image, imported and cached on first access.
  YuvImage get image => _image ??= _load();

  /// Packed, oriented image, computed and cached on first access.
  YuvImage upright() => _upright ??= orientation == YuvFrameOrientation.upright ? image.copy().pack() : orientation.applyTo(image.copy().pack());
}
