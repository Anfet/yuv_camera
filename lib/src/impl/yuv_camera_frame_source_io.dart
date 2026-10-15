import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_layout.dart';
import 'package:yuv_camera/src/camera_image_import.dart';
import 'package:yuv_camera/src/camera_orientation.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  YuvCameraFrameSourceImpl(this.controller, {required this.onFrame, required this.onError});

  final CameraController controller;
  final void Function(YuvCameraFrame frame) onFrame;
  final void Function(Object error) onError;
  final Stopwatch _clock = Stopwatch();
  StreamSubscription<CameraImageData>? _subscription;
  Future<void> _previousStop = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> start() async {
    stop();
    final generation = _generation;
    await _previousStop;
    if (_disposed || generation != _generation) return;
    if (!controller.value.isInitialized) {
      _fail(StateError('CameraController should be initialized'), generation);
      return;
    }
    if (controller.value.isStreamingImages) {
      _fail(
        StateError('CameraController already has an active image stream. YuvCameraFrameSource requires exclusive frame-stream ownership.'),
        generation,
      );
      return;
    }
    _clock
      ..reset()
      ..start();
    try {
      _subscription = CameraPlatform.instance
          .onStreamedFrameAvailable(controller.cameraId)
          .listen(
            (data) => _deliver(CameraImage.fromPlatformInterface(data), generation),
            onError: (Object error) => _fail(error, generation),
            onDone: () => _fail(StateError('Camera image stream ended unexpectedly'), generation),
          );
    } catch (error) {
      _fail(error, generation);
    }
  }

  void _deliver(CameraImage image, int generation) {
    if (_disposed || generation != _generation) return;
    late final YuvPixelFormat format;
    try {
      format = validateCameraImageLayout(image);
    } on FormatException catch (error) {
      final group = image.format.group;
      _fail(
        group == ImageFormatGroup.yuv420 || group == ImageFormatGroup.bgra8888
            ? error
            : UnsupportedError('Unsupported camera image format: $group. Use ImageFormatGroup.yuv420 or ImageFormatGroup.bgra8888.'),
        generation,
      );
      return;
    }
    final platform = _platform();
    final orientation = cameraFrameOrientation(
      platform: platform,
      lensDirection: controller.description.lensDirection,
      sensorOrientation: controller.description.sensorOrientation,
      deviceOrientation: controller.value.deviceOrientation,
    );
    onFrame(
      YuvCameraFrame(
        width: image.width,
        height: image.height,
        format: format,
        orientation: orientation,
        timestamp: _clock.elapsed,
        load: () => importCameraImage(image),
      ),
    );
  }

  void _fail(Object error, int generation) {
    if (_disposed || generation != _generation) return;
    stop();
    onError(error);
  }

  @override
  void stop() {
    _generation++;
    _clock.stop();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _previousStop = subscription.cancel().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('stopping a camera frame stream')),
        );
      });
    }
  }

  Future<void> stopAndWait() async {
    stop();
    await _previousStop;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }
}

TargetPlatform _platform() {
  final override = debugDefaultTargetPlatformOverride;
  if (kDebugMode && override != null) return override;
  return switch (Platform.operatingSystem) {
    'android' => TargetPlatform.android,
    'ios' => TargetPlatform.iOS,
    'linux' => TargetPlatform.linux,
    'macos' => TargetPlatform.macOS,
    'windows' => TargetPlatform.windows,
    _ => throw UnsupportedError('Unsupported camera platform'),
  };
}
