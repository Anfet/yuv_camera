import 'package:camera/camera.dart';

import 'impl/yuv_camera_frame_source_web.dart' if (dart.library.io) 'impl/yuv_camera_frame_source_io.dart' as impl;
import 'yuv_camera_frame.dart';

/// Delivers every camera frame and leaves throttling to its consumer.
abstract interface class YuvCameraFrameSource {
  factory YuvCameraFrameSource(
    CameraController controller, {
    required void Function(YuvCameraFrame frame) onFrame,
    required void Function(Object error) onError,
  }) = impl.YuvCameraFrameSourceImpl;

  Future<void> start();
  void stop();
  void dispose();
}
