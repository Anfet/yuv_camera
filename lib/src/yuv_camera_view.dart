import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';

/// Shader-backed camera preview with independent, throttled frame processing.
///
/// Heavy synchronous work in [onFrame] still blocks the UI isolate and stops
/// painting; use an isolate when the operation supports it.
class YuvCameraView extends StatefulWidget {
  /// Creates a preview for [cameraController], which must be initialized.
  ///
  /// On native platforms the controller's `imageFormatGroup` must be the plugin default, `ImageFormatGroup.yuv420` or
  /// `ImageFormatGroup.bgra8888`; another group stops the stream with an [UnsupportedError] on the first frame, and the
  /// view shows the error.
  const YuvCameraView({
    super.key,
    required this.cameraController,
    this.viewController,
    this.fit = YuvFrameFit.cover,
    this.alignment = Alignment.center,
    this.onFrame,
    this.onFrameInterval = const Duration(milliseconds: 200),
    this.overlayBuilder,
    this.onStreamStopped,
    this.onFramePresented,
  });

  /// Initialized controller whose frames are shown.
  final CameraController cameraController;

  /// Optional handle for capturing the drawn frame and reading its geometry.
  final YuvCameraViewController? viewController;

  /// How the frame is fitted into the available space.
  final YuvFrameFit fit;

  /// Where the frame is placed inside the available space.
  final Alignment alignment;

  /// Called with a frame at most once per [onFrameInterval] and never concurrently with itself.
  ///
  /// An error it throws is reported through `FlutterError.reportError`.
  final FutureOr<void> Function(YuvCameraFrame frame)? onFrame;

  /// Minimum frame time between two [onFrame] calls.
  final Duration onFrameInterval;

  /// Builds an overlay in the geometry of the currently displayed frame.
  final Widget Function(BuildContext context, YuvFrameGeometry geometry)? overlayBuilder;

  /// Called after a stream error has stopped the frame stream.
  /// Not called when the view is removed or given another controller.
  final VoidCallback? onStreamStopped;

  /// Reports each frame confirmed as drawn; [hasShader] is its renderer state.
  final ValueChanged<bool>? onFramePresented;

  @override
  State<YuvCameraView> createState() => _YuvCameraViewState();
}

class _YuvCameraViewState extends State<YuvCameraView> {
  late final YuvFramePresenter _presenter = YuvFramePresenter(useShader: true, onFramePresented: _onPresented);
  YuvCameraFrameSource? _source;
  YuvCameraFrame? _presentedCandidate;
  YuvFrameGeometry? _geometry;
  Completer<YuvImage?>? _capture;
  int _sourceGeneration = 0;
  Duration? _lastOnFrame;
  bool _onFrameRunning = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.viewController?.attach(_requestCapture);
    _start();
  }

  @override
  void didUpdateWidget(covariant YuvCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewController != widget.viewController) {
      oldWidget.viewController?.detach(_requestCapture);
      widget.viewController?.attach(_requestCapture);
    }
    final cameraReplaced = oldWidget.cameraController != widget.cameraController;
    if (cameraReplaced) {
      _stop();
      _error = null;
      _start();
    } else if (oldWidget.viewController != widget.viewController) {
      _publishGeometryAfterBuild();
    }
  }

  /// Gives a replacement handle the geometry already known; listeners must not be notified during build.
  void _publishGeometryAfterBuild() {
    final viewController = widget.viewController;
    if (viewController == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final geometry = _geometry;
      if (mounted && geometry != null && widget.viewController == viewController) viewController.setGeometry(geometry);
    });
  }

  void _start() {
    final source = YuvCameraFrameSource(widget.cameraController, onFrame: _onFrame, onError: _onError);
    _source = source;
    source.start();
  }

  void _onFrame(YuvCameraFrame frame) {
    _dispatchFrameCallback(frame);
    if (_presenter.isBusy) return;
    try {
      if (_presenter.present(frame.image, orientation: frame.orientation)) {
        _presentedCandidate = frame;
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('presenting a camera frame')),
      );
    }
  }

  void _dispatchFrameCallback(YuvCameraFrame frame) {
    final callback = widget.onFrame;
    if (callback == null || _onFrameRunning) return;
    if (_lastOnFrame case final last? when frame.timestamp - last < widget.onFrameInterval) return;
    _lastOnFrame = frame.timestamp;
    _onFrameRunning = true;
    Future<void>.sync(() => callback(frame))
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('processing a camera frame')),
          );
        })
        .whenComplete(() => _onFrameRunning = false);
  }

  void _onGeometry(YuvFrameGeometry geometry) {
    _geometry = geometry;
    widget.viewController?.setGeometry(geometry);
    if (mounted) setState(() {});
  }

  void _onPresented() {
    final capture = _capture;
    final frame = _presentedCandidate;
    final source = _source;
    widget.onFramePresented?.call(_presenter.hasShader);
    if (capture != null && frame != null && source != null) {
      final generation = _sourceGeneration;
      scheduleMicrotask(() {
        if (!mounted || generation != _sourceGeneration || !identical(_source, source) || !identical(_capture, capture)) {
          return;
        }
        final geometry = _geometry;
        if (geometry == null ||
            geometry.sourceSize != Size(frame.width.toDouble(), frame.height.toDouble()) ||
            geometry.orientation != frame.orientation) {
          return;
        }
        _capture = null;
        try {
          final fullSource = Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble());
          capture.complete(
            geometry.visibleSourceRect == fullSource && frame.orientation == YuvFrameOrientation.upright
                ? frame.image.copy()
                : geometry.apply(frame.image),
          );
        } catch (error, stack) {
          capture.completeError(error, stack);
        }
      });
    }
  }

  Future<YuvImage?> _requestCapture() {
    if (_error != null) return Future<YuvImage?>.value(null);
    final pending = _capture;
    if (pending != null && !pending.isCompleted) return pending.future;
    final next = _capture = Completer<YuvImage?>();
    return next.future;
  }

  void _onError(Object error) {
    _completeCapture(null);
    if (mounted) setState(() => _error = error);
    widget.onStreamStopped?.call();
  }

  void _completeCapture(YuvImage? image) {
    final capture = _capture;
    _capture = null;
    if (capture != null && !capture.isCompleted) capture.complete(image);
  }

  void _stop() {
    _sourceGeneration++;
    _source?.dispose();
    _source = null;
    _presenter.reset();
    _presentedCandidate = null;
    // Frame timestamps restart with every source; an old mark would hold onFrame back until the new clock passes it.
    _lastOnFrame = null;
    _completeCapture(null);
  }

  @override
  void dispose() {
    widget.viewController?.detach(_requestCapture);
    _stop();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return Center(child: Text('Camera error: $error', textAlign: TextAlign.center));
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvFrameView(presenter: _presenter, fit: widget.fit, alignment: widget.alignment, onGeometryChanged: _onGeometry),
        if (_geometry case final geometry?) widget.overlayBuilder?.call(context, geometry) ?? const SizedBox.shrink(),
      ],
    );
  }
}
