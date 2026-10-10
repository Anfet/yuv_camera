import 'package:camera/camera.dart';

import 'impl/yuv_camera_frame_source_web.dart' if (dart.library.io) 'impl/yuv_camera_frame_source_io.dart' as impl;
import 'yuv_camera_frame.dart';

/// Delivers every camera frame and leaves throttling to its consumer.
abstract interface class YuvCameraFrameSource {
  /// Creates the source for the current platform: `camera` streaming on native platforms and a browser media stream on Web.
  ///
  /// [controller] must be initialized. [onFrame] receives every frame; [onError] receives a stream failure after which the
  /// source has stopped.
  factory YuvCameraFrameSource(
    CameraController controller, {
    required void Function(YuvCameraFrame frame) onFrame,
    required void Function(Object error) onError,
  }) = impl.YuvCameraFrameSourceImpl;

  /// Starts delivering frames, replacing any running delivery.
  Future<void> start();

  /// Stops delivering frames; [start] may be called again.
  void stop();

  /// Stops delivering frames permanently.
  void dispose();
}
