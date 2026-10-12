import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

/// Camera preview whose accepted frames are synchronously transformed first.
class YuvTransformView extends StatefulWidget {
  /// Creates a preview for [cameraController], which must be initialized, drawing the result of [transform].
  ///
  /// On native platforms the controller's `imageFormatGroup` must be the plugin default, `ImageFormatGroup.yuv420` or
  /// `ImageFormatGroup.bgra8888`; another group stops the stream with an [UnsupportedError] on the first frame, and the
  /// view shows the error.
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
