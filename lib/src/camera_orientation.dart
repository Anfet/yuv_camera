import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Derives the draw-time orientation of a delivered camera frame.
YuvFrameOrientation cameraFrameOrientation({
  required TargetPlatform platform,
  required CameraLensDirection lensDirection,
  required int sensorOrientation,
  required DeviceOrientation deviceOrientation,
}) {
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
