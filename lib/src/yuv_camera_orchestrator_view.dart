import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_orchestrator.dart';
import 'package:yuv_camera/src/yuv_camera_view.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';

/// A [YuvCameraView] that leases its camera from an [orchestrator] while it is mounted.
///
/// The lease is taken when the widget is inserted and released when it is removed, after the preview has stopped its
/// frame stream. Until the camera is open, or when it cannot be opened, [placeholderBuilder] is shown.
class YuvCameraOrchestratorView extends StatefulWidget {
  /// Creates a preview of the camera owned by [orchestrator]; the other parameters are passed to [YuvCameraView].
  const YuvCameraOrchestratorView({
    super.key,
    required this.orchestrator,
    this.viewController,
    this.fit = YuvFrameFit.cover,
    this.alignment = Alignment.center,
    this.onFrame,
    this.onFrameInterval = const Duration(milliseconds: 200),
    this.overlayBuilder,
    this.onStreamStopped,
    this.onFramePresented,
    this.placeholderBuilder,
  });

  /// Owner of the camera this preview leases.
  final YuvCameraOrchestrator orchestrator;

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

  /// Called when the frame stream stops, including after a stream error.
  final VoidCallback? onStreamStopped;

  /// Reports each frame confirmed as drawn; [hasShader] is its renderer state.
  final ValueChanged<bool>? onFramePresented;

  /// Builds the content shown while the camera opens; `error` is the opening failure, or `null` while opening.
  ///
  /// Without it a centered progress indicator is shown while opening and a centered message on failure.
  final Widget Function(BuildContext context, Object? error)? placeholderBuilder;

  @override
  State<YuvCameraOrchestratorView> createState() => _YuvCameraOrchestratorViewState();
}

class _YuvCameraOrchestratorViewState extends State<YuvCameraOrchestratorView> {
  @override
  Widget build(BuildContext context) {
    final lease = _lease;
    if (lease == null) return _buildPlaceholder(context);
    return YuvCameraView(
      cameraController: lease.controller,
      viewController: widget.viewController,
      fit: widget.fit,
      alignment: widget.alignment,
      onFrame: widget.onFrame,
      onFrameInterval: widget.onFrameInterval,
      overlayBuilder: widget.overlayBuilder,
      onStreamStopped: widget.onStreamStopped,
      onFramePresented: widget.onFramePresented,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final error = _error;
    if (widget.placeholderBuilder case final builder?) return builder(context, error);
    if (error != null) return Center(child: Text('Camera unavailable: $error', textAlign: TextAlign.center));
    return const Center(child: CircularProgressIndicator());
  }

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  @override
  void didUpdateWidget(covariant YuvCameraOrchestratorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orchestrator == widget.orchestrator) return;
    final previous = _lease;
    _lease = null;
    _error = null;
    _acquire();
    // The previous preview is unmounted by the frame being built; releasing afterwards stops its stream first.
    if (previous != null) WidgetsBinding.instance.addPostFrameCallback((_) => previous.release());
  }

  @override
  void dispose() {
    _request++;
    _lease?.release();
    super.dispose();
  }

  Future<void> _acquire() async {
    final request = ++_request;
    try {
      final lease = await widget.orchestrator.acquire();
      if (!mounted || request != _request) {
        lease.release();
        return;
      }
      setState(() => _lease = lease);
    } catch (error) {
      // A request abandoned by unmounting or by a new orchestrator drops its failure; the orchestrator keeps it in
      // `error` for its listeners.
      if (!mounted || request != _request) return;
      setState(() => _error = error);
    }
  }

  YuvCameraLease? _lease;
  Object? _error;
  int _request = 0;
}
