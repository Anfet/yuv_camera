import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension YuvImageToCameraExt on YuvImage {
  /// Builds an [InputImage] whose bytes match its declared metadata format.
  InputImage toInputImage({InputImageRotation rotation = InputImageRotation.rotation0deg}) {
    switch (format) {
      case YuvPixelFormat.i420:
      case YuvPixelFormat.nv12:
        final bytes = _toNv21Bytes();
        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(size: size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: width),
        );
      case YuvPixelFormat.bgra8888:
        // ML Kit on iOS reads no face from BGRA whose row length is not a multiple of 16 bytes, even with a matching
        // bytesPerRow, so narrower rows are right-padded with transparent pixels; the image origin does not move.
        final paddedWidth = (width + 3) ~/ 4 * 4;
        final bytes = _toBgraBytes(paddedWidth);
        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(paddedWidth.toDouble(), height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: paddedWidth * 4,
          ),
        );
    }
  }

  Uint8List _toBgraBytes(int paddedWidth) {
    final tight = copy().pack().yPlane.bytes;
    if (paddedWidth == width) return tight;
    final rowBytes = width * 4;
    final paddedRowBytes = paddedWidth * 4;
    final result = Uint8List(paddedRowBytes * height);
    for (var row = 0; row < height; row++) {
      result.setRange(row * paddedRowBytes, row * paddedRowBytes + rowBytes, tight, row * rowBytes);
    }
    return result;
  }

  Uint8List _toNv21Bytes() {
    final tight = copy().pack();
    final chromaWidth = (width + 1) ~/ 2;
    final chromaHeight = (height + 1) ~/ 2;
    final vu = Uint8List(chromaHeight * chromaWidth * 2);
    if (tight.format == YuvPixelFormat.nv12) {
      final uv = tight.uPlane.bytes;
      for (var i = 0; i < chromaWidth * chromaHeight; i++) {
        vu[i * 2] = uv[i * 2 + 1];
        vu[i * 2 + 1] = uv[i * 2];
      }
    } else {
      final u = tight.uPlane.bytes;
      final v = tight.vPlane.bytes;
      for (var i = 0; i < chromaWidth * chromaHeight; i++) {
        vu[i * 2] = v[i];
        vu[i * 2 + 1] = u[i];
      }
    }
    final result = Uint8List(tight.yPlane.bytes.length + vu.length);
    result.setRange(0, tight.yPlane.bytes.length, tight.yPlane.bytes);
    result.setRange(tight.yPlane.bytes.length, result.length, vu);
    return result;
  }
}
