import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

import 'impl/yuv_camera_frame_source_web.dart' if (dart.library.io) 'impl/yuv_camera_frame_source_io.dart' as impl;
import 'yuv_camera_frame.dart';

/// Delivers every camera frame and leaves throttling to its consumer.
abstract interface class YuvCameraFrameSource {
  /// Creates the source for the current platform: `camera` streaming on native platforms and a browser media stream on Web.
  ///
  /// [controller] must be initialized. [onFrame] receives every frame; [onError] receives a stream failure after which the
  /// source has stopped.
  /// Multiple sources created for the same controller share one platform stream; each source can stop independently.
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
  }) {
    final hub = _hubs[controller] ??= _CameraFrameSourceHub(controller);
    return hub.createConsumer(onFrame: onFrame, onError: onError);
  }

  /// Starts delivering frames, replacing any running delivery.
  Future<void> start();

  /// Stops delivering frames; [start] may be called again.
  void stop();

  /// Stops delivering frames permanently.
  void dispose();
}

final Expando<_CameraFrameSourceHub> _hubs = Expando<_CameraFrameSourceHub>();

final class _CameraFrameSourceHub {
  _CameraFrameSourceHub(this._controller) {
    _backend = impl.YuvCameraFrameSourceImpl(_controller, onFrame: _deliver, onError: _fail);
  }

  final CameraController _controller;
  final Set<_FrameSourceConsumer> _consumers = {};
  late final impl.YuvCameraFrameSourceImpl _backend;
  Future<void>? _opening;
  bool _terminal = false;

  YuvCameraFrameSource createConsumer({required void Function(YuvCameraFrame frame) onFrame, required void Function(Object error) onError}) {
    final consumer = _FrameSourceConsumer(this, onFrame, onError);
    _consumers.add(consumer);
    return consumer;
  }

  Future<void> start(_FrameSourceConsumer consumer) async {
    if (consumer._disposed) return;
    final wasIdle = !_consumers.any((item) => item._running);
    consumer._begin();
    if (wasIdle || _terminal) {
      _terminal = false;
      final previousOpening = _opening;
      final opening = _opening = previousOpening == null ? _backend.start() : previousOpening.then((_) => _backend.start());
      try {
        await opening;
      } finally {
        if (identical(_opening, opening)) _opening = null;
      }
    } else if (_opening case final opening?) {
      await opening;
    }
  }

  void stop(_FrameSourceConsumer consumer) {
    if (!consumer._running) return;
    consumer._end();
    if (!_consumers.any((item) => item._running)) _backend.stop();
  }

  void dispose(_FrameSourceConsumer consumer) {
    stop(consumer);
    consumer._disposed = true;
    _consumers.remove(consumer);
  }

  void _deliver(YuvCameraFrame frame) {
    for (final consumer in _consumers.toList()) {
      if (!consumer._running) continue;
      try {
        consumer._onFrame(
          YuvCameraFrame(
            width: frame.width,
            height: frame.height,
            format: frame.format,
            orientation: frame.orientation,
            timestamp: consumer._clock.elapsed,
            load: () => frame.image,
          ),
        );
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('delivering a camera frame')),
        );
      }
    }
  }

  void _fail(Object error) {
    if (_terminal) return;
    _terminal = true;
    for (final consumer in _consumers.toList()) {
      if (!consumer._running) continue;
      consumer._end();
      try {
        consumer._onError(error);
      } catch (callbackError, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: callbackError,
            stack: stack,
            library: 'yuv_camera',
            context: ErrorDescription('reporting a camera stream error'),
          ),
        );
      }
    }
  }
}

final class _FrameSourceConsumer implements YuvCameraFrameSource {
  _FrameSourceConsumer(this._hub, this._onFrame, this._onError);

  final _CameraFrameSourceHub _hub;
  final void Function(YuvCameraFrame frame) _onFrame;
  final void Function(Object error) _onError;
  final Stopwatch _clock = Stopwatch();
  bool _running = false;
  bool _disposed = false;

  @override
  Future<void> start() => _hub.start(this);

  @override
  void stop() => _hub.stop(this);

  @override
  void dispose() => _hub.dispose(this);

  void _begin() {
    _running = true;
    _clock
      ..reset()
      ..start();
  }

  void _end() {
    _running = false;
    _clock.stop();
  }
}
