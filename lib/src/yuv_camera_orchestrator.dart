import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_camera/src/camera_stream_lifecycle.dart';

/// Lifecycle state of the camera owned by a [YuvCameraOrchestrator].
enum YuvCameraState {
  /// No camera controller exists.
  closed,

  /// A camera is being looked up and initialized.
  opening,

  /// An initialized controller is available through [YuvCameraOrchestrator.controller].
  open,

  /// The controller is being disposed.
  closing,
}

/// Owns the single camera of an app and hands it out as leases.
///
/// Screens call [acquire] for a [YuvCameraLease] and [YuvCameraLease.release] it when they no longer show the camera.
/// The first lease opens the camera; releasing the last one closes it after [closeDelay], and a lease taken within
/// that delay keeps the same controller. All transitions run one after another, so at most one controller is alive at
/// any time: a request made while the camera is closing waits for the old controller to be disposed first.
///
/// The orchestrator does not observe the app lifecycle. YuvCameraLeaseBuilder releases its lease while the app is
/// hidden; the app must release manually acquired leases itself when it goes to the background.
///
/// A terminal controller or frame-source error invalidates active leases, drains frame subscriptions before disposal,
/// and leaves the orchestrator closed with [error] set. A later [acquire] opens a fresh controller.
///
/// Listeners are notified asynchronously in a microtask when [state] or [error] changes. Getters change immediately;
/// one notification can cover several transitions in the same turn. No notifications are delivered after [dispose].
class YuvCameraOrchestrator extends ChangeNotifier {
  /// Creates an orchestrator that opens the first camera facing [lensDirection], or the first camera when none does.
  ///
  /// [resolution] and [fps] are passed to the [CameraController]; audio is never enabled.
  YuvCameraOrchestrator({
    this.lensDirection = CameraLensDirection.front,
    this.resolution = ResolutionPreset.medium,
    this.fps,
    this.closeDelay = Duration.zero,
  });

  /// Preferred direction of the opened camera.
  final CameraLensDirection lensDirection;

  /// Resolution preset of the opened camera.
  final ResolutionPreset resolution;

  /// Requested frame rate, or `null` for the platform default.
  final int? fps;

  /// How long the camera stays open after the last lease is released.
  final Duration closeDelay;

  /// Current lifecycle state.
  YuvCameraState get state => _state;

  /// The initialized controller; not `null` only in [YuvCameraState.open].
  CameraController? get controller => _controller;

  /// Error of the last failed opening; reset when the next opening starts.
  Object? get error => _error;

  /// Returns a lease on the open camera, opening it first when needed.
  ///
  /// Concurrent calls share one opening and one controller. A call made while the camera is closing waits for the
  /// close and then opens a new controller. When the camera cannot be found or initialized, every pending call
  /// completes with that error (a [CameraException] with code `noCamera` when the device has no camera) and the next
  /// call tries again.
  ///
  /// Throws a [StateError] when the orchestrator is disposed before or while the lease is being acquired.
  Future<YuvCameraLease> acquire() async {
    _throwIfDisposed();
    _cancelCloseTimer();
    _pendingAcquires++;
    try {
      while (true) {
        if (_controller case final controller?) {
          final lease = YuvCameraLease._(controller, _release);
          _leases.add(lease);
          return lease;
        }
        await _awaitTransition(_transition ?? _open());
      }
    } finally {
      _pendingAcquires--;
    }
  }

  /// Closes the camera and rejects further [acquire] calls.
  ///
  /// Waits for an opening in progress and then disposes the controller at once, ignoring [closeDelay] and outstanding
  /// leases; pending [acquire] calls complete with a [StateError]. Listeners are not notified afterwards. Repeated calls
  /// return the same future.
  @override
  Future<void> dispose() {
    if (_disposing case final disposing?) return disposing;
    _isDisposed = true;
    _cancelCloseTimer();
    _revokeLeases();
    super.dispose();
    return _disposing = _closeAfterTransition();
  }

  void _release(YuvCameraLease lease) {
    if (!_leases.remove(lease) || _leases.isNotEmpty) return;
    if (closeDelay == Duration.zero) {
      _closeIfIdle();
    } else {
      _cancelCloseTimer();
      _closeTimer = Timer(closeDelay, () {
        _closeTimer = null;
        _closeIfIdle();
      });
    }
  }

  void _closeIfIdle() {
    if (_leases.isNotEmpty || _pendingAcquires > 0) return;
    if (_controller case final controller?) _close(controller).ignore();
  }

  Future<void> _awaitTransition(Future<void> transition) async {
    try {
      await transition;
    } catch (_) {
      _throwIfDisposed();
      rethrow;
    }
    _throwIfDisposed();
  }

  // The transition is stored before listeners hear the new state, so a listener calling acquire() joins it.
  Future<void> _open() {
    _error = null;
    _state = YuvCameraState.opening;
    final opening = _transition = _initialize();
    _notify();
    return opening;
  }

  Future<void> _initialize() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('noCamera', 'No camera is available.');
      final description = cameras.firstWhere((camera) => camera.lensDirection == lensDirection, orElse: () => cameras.first);
      controller = CameraController(description, resolution, enableAudio: false, fps: fps);
      await controller.initialize();
      if (controller.value.hasError) {
        throw StateError(controller.value.errorDescription ?? 'The camera controller reported an error.');
      }
      final activeController = controller;
      void listener() => _controllerChanged(activeController);
      activeController.addListener(listener);
      _controllerListeners[activeController] = listener;
      void lifecycleListener(Object error) => _terminalController(activeController, error);
      final lifecycle = CameraStreamLifecycle.forController(activeController);
      lifecycle.addErrorListener(lifecycleListener);
      _lifecycleListeners[activeController] = lifecycleListener;
      try {
        _cameraErrorSubscriptions[activeController] = CameraPlatform.instance
            .onCameraError(activeController.cameraId)
            .listen(
              (event) => _terminalController(activeController, CameraException('cameraError', event.description)),
              onError: (Object error) => _terminalController(activeController, error),
            );
      } on UnimplementedError {
        // Older/custom platform implementations may expose errors only through CameraController.value.
      }
      if (activeController.value.hasError) {
        throw StateError(activeController.value.errorDescription ?? 'The camera controller reported an error.');
      }
    } catch (error) {
      if (controller != null) await _disposeController(controller);
      _transition = null;
      _error = error;
      _setState(YuvCameraState.closed);
      rethrow;
    }
    _transition = null;
    _controller = controller;
    _setState(YuvCameraState.open);
  }

  Future<void> _close(CameraController controller) {
    _controller = null;
    _state = YuvCameraState.closing;
    final closing = _transition = _finishClose(controller);
    _notify();
    return closing;
  }

  Future<void> _finishClose(CameraController controller) async {
    await _disposeController(controller);
    _transition = null;
    _setState(YuvCameraState.closed);
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      final listener = _controllerListeners.remove(controller);
      if (listener != null) controller.removeListener(listener);
      final cameraErrorSubscription = _cameraErrorSubscriptions.remove(controller);
      if (cameraErrorSubscription != null) {
        try {
          await cameraErrorSubscription.cancel();
        } catch (error, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('cancelling camera error events')),
          );
        }
      }
      final lifecycle = CameraStreamLifecycle.forController(controller);
      final lifecycleListener = _lifecycleListeners.remove(controller);
      if (lifecycleListener != null) lifecycle.removeErrorListener(lifecycleListener);
      await lifecycle.close();
      await controller.dispose();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'yuv_camera', context: ErrorDescription('disposing a camera controller')),
      );
    }
  }

  void _controllerChanged(CameraController controller) {
    if (!identical(_controller, controller) || !controller.value.hasError) return;
    final error = StateError(controller.value.errorDescription ?? 'The camera controller reported an error.');
    // Let frame-source listeners report the terminal failure to their consumers first.
    scheduleMicrotask(() => _terminalController(controller, error));
  }

  void _terminalController(CameraController controller, Object error) {
    if (!identical(_controller, controller)) return;
    _error = error;
    _revokeLeases();
    _close(controller).ignore();
  }

  void _revokeLeases() {
    for (final lease in _leases) {
      lease._revoke();
    }
    _leases.clear();
  }

  Future<void> _closeAfterTransition() async {
    try {
      await _transition;
    } catch (_) {
      // The failed opening already completed every pending acquire() with this error and is kept in [error].
    }
    if (_controller case final controller?) await _close(controller);
  }

  void _setState(YuvCameraState state) {
    if (_state == state) return;
    _state = state;
    _notify();
  }

  void _notify() {
    if (_isDisposed || _notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_isDisposed) notifyListeners();
    });
  }

  void _cancelCloseTimer() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void _throwIfDisposed() {
    if (_isDisposed) throw StateError('The camera orchestrator was disposed.');
  }

  YuvCameraState _state = YuvCameraState.closed;
  CameraController? _controller;
  Object? _error;
  Future<void>? _transition;
  Future<void>? _disposing;
  Timer? _closeTimer;
  int _pendingAcquires = 0;
  bool _isDisposed = false;
  bool _notificationScheduled = false;
  final Set<YuvCameraLease> _leases = {};
  final Map<CameraController, VoidCallback> _controllerListeners = {};
  final Map<CameraController, void Function(Object error)> _lifecycleListeners = {};
  final Map<CameraController, StreamSubscription<CameraErrorEvent>> _cameraErrorSubscriptions = {};
}

/// A claim on the camera of a [YuvCameraOrchestrator], returned by [YuvCameraOrchestrator.acquire].
///
/// The camera stays open while at least one lease is not released.
final class YuvCameraLease {
  YuvCameraLease._(this._controller, this._onRelease);

  /// The initialized controller of the leased camera.
  ///
  /// Throws a [StateError] after [release] or when the camera owner revokes this lease.
  CameraController get controller {
    if (_isReleased || _isRevoked) throw StateError('The camera lease is no longer valid.');
    return _controller;
  }

  /// Whether [release] was called.
  bool get isReleased => _isReleased;

  /// Gives the camera back to the orchestrator; later calls do nothing.
  void release() {
    if (_isReleased) return;
    _isReleased = true;
    _onRelease(this);
  }

  void _revoke() => _isRevoked = true;

  final CameraController _controller;
  final void Function(YuvCameraLease lease) _onRelease;
  bool _isReleased = false;
  bool _isRevoked = false;
}
