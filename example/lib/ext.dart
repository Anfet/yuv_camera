import 'dart:typed_data';

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
        final tight = copy().pack();
        return InputImage.fromBytes(
          bytes: tight.yPlane.bytes,
          metadata: InputImageMetadata(size: size, rotation: rotation, format: InputImageFormat.bgra8888, bytesPerRow: width * 4),
        );
    }
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
