import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/src/yuv_camera_orchestrator.dart';

/// Leases an initialized camera for [builder] while mounted and the app is visible.
///
/// The child can be a YuvCameraView, YuvTransformView or another widget using the controller. It is removed before the
/// lease is released on hide or an orchestrator change, so its frame stream stops before the camera closes. Inactive
/// lifecycle transitions do not release the lease, including camera permission prompts on Android.
class YuvCameraLeaseBuilder extends StatefulWidget {
  /// Builds with the camera owned by [orchestrator], or shows [placeholderBuilder] while opening or after a failure.
  const YuvCameraLeaseBuilder({super.key, required this.orchestrator, required this.builder, this.placeholderBuilder});

  /// Owner of the leased camera.
  final YuvCameraOrchestrator orchestrator;

  /// Builds the child with the initialized, leased camera controller.
  final Widget Function(BuildContext context, CameraController controller) builder;

  /// Builds content without a lease: error is the opening failure, or null while opening or hidden.
  ///
  /// Retry starts a new attempt after failure; it does nothing while hidden, opening or already leased. Without this
  /// builder, a progress indicator is shown while opening and an error message with a Retry button on failure.
  final Widget Function(BuildContext context, Object? error, VoidCallback retry)? placeholderBuilder;

  @override
  State<YuvCameraLeaseBuilder> createState() => _YuvCameraLeaseBuilderState();
}

class _YuvCameraLeaseBuilderState extends State<YuvCameraLeaseBuilder> {
  @override
  Widget build(BuildContext context) {
    if (_lease case final lease?) return widget.builder(context, lease.controller);
    if (widget.placeholderBuilder case final builder?) return builder(context, _error, _acquire);
    if (_error case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Camera unavailable: $error', textAlign: TextAlign.center),
            TextButton(onPressed: _acquire, child: const Text('Retry')),
          ],
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  @override
  void initState() {
    super.initState();
    _visible =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden && WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
    _lifecycleListener = AppLifecycleListener(onHide: _hide, onShow: _show);
    _acquire();
  }

  @override
  void didUpdateWidget(covariant YuvCameraLeaseBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orchestrator == widget.orchestrator) return;
    _releaseAfterFrame();
    _error = null;
    _acquire();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _request++;
    _lease?.release();
    super.dispose();
  }

  void _hide() {
    setState(() {
      _visible = false;
      _error = null;
      _releaseAfterFrame();
    });
    // Hidden apps stop scheduling normal frames; finish unmounting the preview and releasing its lease now.
    WidgetsBinding.instance.scheduleWarmUpFrame();
  }

  void _show() {
    _visible = true;
    _acquire();
  }

  void _releaseAfterFrame() {
    _request++;
    _acquiring = false;
    final previous = _lease;
    _lease = null;
    // The frame unmounts the child before the camera can close.
    if (previous != null) WidgetsBinding.instance.addPostFrameCallback((_) => previous.release());
  }

  Future<void> _acquire() async {
    if (!_visible || _acquiring || _lease != null) return;
    final request = ++_request;
    setState(() {
      _acquiring = true;
      _error = null;
    });
    try {
      final lease = await widget.orchestrator.acquire();
      if (!mounted || request != _request) {
        lease.release();
        return;
      }
      setState(() {
        _acquiring = false;
        _lease = lease;
      });
    } catch (error) {
      // Abandoned requests leave their failure on the orchestrator for its listeners.
      if (!mounted || request != _request) return;
      setState(() {
        _acquiring = false;
        _error = error;
      });
    }
  }

  late final AppLifecycleListener _lifecycleListener;
  YuvCameraLease? _lease;
  Object? _error;
  int _request = 0;
  bool _acquiring = false;
  bool _visible = true;
}
