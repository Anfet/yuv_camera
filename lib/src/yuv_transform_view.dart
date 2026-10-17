import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

/// Camera preview whose accepted frames are synchronously transformed first.
///
/// Await `YuvFfi.initialize()` in the current isolate before starting a transform
/// that performs image operations; worker isolates must initialize separately.
/// A stream error replaces the preview with English `Camera error: ...` text.
/// Provide Flutter text direction, text style and theme context, normally through
/// `MaterialApp` and `Scaffold`.
///
/// [transform] must return an upright image. The view copies the returned image
/// for drawing; copy a delivered frame image before mutating it.
class YuvTransformView extends StatefulWidget {
  /// Creates a preview for [cameraController], which must be initialized, drawing the result of [transform].
  ///
  /// Native two-plane `yuv420` frames are imported as NV12, three-plane frames as I420, and one-plane BGRA stays packed.
  /// Controller errors, stream failures, unsupported formats and malformed layouts stop the stream and reach
  /// [onStreamStopped].
  const YuvTransformView({
    super.key,
    required this.cameraController,
    required this.transform,
    this.fit = YuvFrameFit.cover,
    this.alignment = Alignment.center,
    this.overlayBuilder,
    this.onStreamStopped,
  });

  /// Initialized controller whose frames are shown.
  final CameraController cameraController;

  /// Synchronously produces the image to draw for an accepted frame; it runs on the UI isolate.
  ///
  /// The returned image is drawn as supplied; the view does not apply the frame orientation again. Use
  /// `frame.upright().copy()` before mutating pixels because the frame owns the image returned by `upright()`.
  /// If this callback throws, the frame is dropped, the error is reported to Flutter, and the stream continues.
  final YuvImage Function(YuvCameraFrame frame) transform;

  /// How the image is fitted into the available space.
  final YuvFrameFit fit;

  /// Where the image is placed inside the available space.
  final Alignment alignment;

  /// Builds an overlay in the geometry of the currently displayed image.
  final Widget Function(BuildContext context, YuvFrameGeometry geometry)? overlayBuilder;

  /// Called after a stream error has stopped the frame stream.
  /// Not called when the view is removed or given another controller.
  final VoidCallback? onStreamStopped;

  @override
  State<YuvTransformView> createState() => _YuvTransformViewState();
}

class _YuvTransformViewState extends State<YuvTransformView> {
  final YuvFramePresenter _presenter = YuvFramePresenter(useShader: true);
  YuvCameraFrameSource? _source;
  YuvFrameGeometry? _geometry;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final source = YuvCameraFrameSource(widget.cameraController, onFrame: _onFrame, onError: _onError);
    _source = source;
    source.start();
  }

  @override
  void didUpdateWidget(covariant YuvTransformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      _source?.dispose();
      _source = null;
      _presenter.reset();
      _geometry = null;
      _error = null;
      _start();
    }
  }

  void _onFrame(YuvCameraFrame frame) {
    if (_presenter.isBusy) return;
    try {
      _presenter.present(widget.transform(frame));
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('transforming a camera frame')),
      );
    }
  }

  void _onError(Object error) {
    _geometry = null;
    if (mounted) setState(() => _error = error);
    widget.onStreamStopped?.call();
  }

  @override
  void dispose() {
    _source?.dispose();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) return Center(child: Text('Camera error: $error'));
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvFrameView(
          presenter: _presenter,
          fit: widget.fit,
          alignment: widget.alignment,
          onGeometryChanged: (geometry) => setState(() => _geometry = geometry),
        ),
        if (_geometry case final geometry?) widget.overlayBuilder?.call(context, geometry) ?? const SizedBox.shrink(),
      ],
    );
  }
}
