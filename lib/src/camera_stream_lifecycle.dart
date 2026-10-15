import 'package:camera/camera.dart';

/// Coordinates frame-source teardown with the owner of a camera controller.
final class CameraStreamLifecycle {
  CameraStreamLifecycle(this.controller);

  final CameraController controller;
  final Set<Future<void> Function()> _drains = {};
  final Set<void Function(Object error)> _errorListeners = {};
  bool _closing = false;

  static final Expando<CameraStreamLifecycle> _instances = Expando<CameraStreamLifecycle>();

  static CameraStreamLifecycle forController(CameraController controller) => _instances[controller] ??= CameraStreamLifecycle(controller);

  bool get isClosing => _closing;

  void registerDrain(Future<void> Function() drain) => _drains.add(drain);

  void unregisterDrain(Future<void> Function() drain) => _drains.remove(drain);

  void addErrorListener(void Function(Object error) listener) => _errorListeners.add(listener);

  void removeErrorListener(void Function(Object error) listener) => _errorListeners.remove(listener);

  void reportError(Object error) {
    for (final listener in List<void Function(Object error)>.of(_errorListeners)) {
      listener(error);
    }
  }

  Future<void> close() async {
    _closing = true;
    await Future.wait([for (final drain in List<Future<void> Function()>.of(_drains)) drain()]);
  }
}
