import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Derives the draw-time orientation of a frame delivered through the `camera` platform interface.
///
/// Android rotates by the sensor and device orientation and mirrors the front camera. Windows mirrors every camera
/// except a back one, without rotation, see [mirroredUnlessBackOrientation]. iOS, macOS and Linux frames are upright
/// and not mirrored.
YuvFrameOrientation cameraFrameOrientation({
  required TargetPlatform platform,
  required CameraLensDirection lensDirection,
  required int sensorOrientation,
  required DeviceOrientation deviceOrientation,
}) {
  if (platform == TargetPlatform.windows) return mirroredUnlessBackOrientation(lensDirection);
  if (platform != TargetPlatform.android) return YuvFrameOrientation.upright;
  final deviceDegrees = switch (deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final front = lensDirection == CameraLensDirection.front;
  final degrees = front ? (sensorOrientation + deviceDegrees) % 360 : (sensorOrientation - deviceDegrees + 360) % 360;
  return YuvFrameOrientation(rotation: YuvImageRotation.values.singleWhere((rotation) => rotation.degrees == degrees), mirrored: front);
}

/// Orientation of a frame that arrives upright from a camera whose own preview is mirrored: Windows (`camera_desktop`)
/// and Web (`camera_web`). Every camera except a back one is mirrored; nothing is rotated.
YuvFrameOrientation mirroredUnlessBackOrientation(CameraLensDirection lensDirection) =>
    lensDirection == CameraLensDirection.back ? YuvFrameOrientation.upright : const YuvFrameOrientation(mirrored: true);
