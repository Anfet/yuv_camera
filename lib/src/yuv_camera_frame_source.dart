import 'package:camera/camera.dart';

import 'impl/yuv_camera_frame_source_web.dart' if (dart.library.io) 'impl/yuv_camera_frame_source_io.dart' as impl;
import 'yuv_camera_frame.dart';

/// Delivers every camera frame and leaves throttling to its consumer.
abstract interface class YuvCameraFrameSource {
  /// Creates the source for the current platform: `camera` streaming on native platforms and a browser media stream on Web.
  ///
  /// [controller] must be initialized. [onFrame] receives every frame; [onError] receives a stream failure after which the
  /// source has stopped.
  ///
  /// On Web the source opens a second media stream on the controller's device,
  /// matched by its unique, non-empty camera label. Empty, missing or duplicate
  /// labels fall back to the lens direction. The controller's resolution preset
  /// and optional fps are requested as `ideal` constraints, which the browser
  /// may adjust. Device enumeration and stream-opening failures reach [onError].
  ///
  /// On native platforms the controller's `imageFormatGroup` must be the plugin default, `ImageFormatGroup.yuv420` or
  /// `ImageFormatGroup.bgra8888`; another group stops the source with an [UnsupportedError] on the first frame.
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
