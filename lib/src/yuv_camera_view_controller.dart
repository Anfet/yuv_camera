import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A handle for observing a [YuvCameraView] and capturing its next drawn frame.
class YuvCameraViewController extends ChangeNotifier {
  final _GeometryListenable _geometry = _GeometryListenable();
  Future<YuvImage?> Function()? _capture;
  Future<YuvImage?> Function()? _geometryOwner;
  YuvFrameGeometry? _notifiedGeometry;
  bool _geometryNotificationScheduled = false;
  bool _disposed = false;

  /// Geometry used for the currently displayed frame.
  ValueListenable<YuvFrameGeometry?> get geometry => _geometry;

  /// Returns the next frame that is actually drawn, cropped to what is visible.
  /// Completes with `null` if the view stops, including when its frame stream fails, before a frame is drawn.
  Future<YuvImage?> capture() => _capture?.call() ?? Future<YuvImage?>.value(null);

  void _attach(Future<YuvImage?> Function() capture) {
    if (_disposed) return;
    _capture = capture;
    _geometryOwner = capture;
    _setGeometryValue(null);
  }

  void _detach(Future<YuvImage?> Function() capture) {
    if (_disposed) return;
    if (_capture != capture) return;
    _capture = null;
    _geometryOwner = null;
    _setGeometryValue(null);
  }

  void _setGeometryFor(Future<YuvImage?> Function() owner, YuvFrameGeometry? geometry) {
    if (_disposed || _geometryOwner != owner) return;
    _setGeometryValue(geometry);
  }

  void _setGeometryValue(YuvFrameGeometry? geometry) {
    if (_geometry.value == geometry) return;
    _geometry.setValue(geometry);

    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle || scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      _notifyGeometryChanged();
      return;
    }

    if (_geometryNotificationScheduled) return;
    _geometryNotificationScheduled = true;
    scheduler.addPostFrameCallback((_) {
      _geometryNotificationScheduled = false;
      if (_disposed) return;
      _notifyGeometryChanged();
    });
  }

  void _notifyGeometryChanged() {
    final geometry = _geometry.value;
    if (geometry == _notifiedGeometry || _disposed) return;
    _notifiedGeometry = geometry;
    _geometry.notifyValueListeners();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _capture = null;
    _geometryOwner = null;
    _geometry.dispose();
    super.dispose();
  }
}

class _GeometryListenable extends ChangeNotifier implements ValueListenable<YuvFrameGeometry?> {
  YuvFrameGeometry? _value;

  @override
  YuvFrameGeometry? get value => _value;

  void setValue(YuvFrameGeometry? value) => _value = value;

  void notifyValueListeners() => notifyListeners();
}

/// Internal binding used by YuvCameraView; hidden from the package export.
extension YuvCameraViewControllerBinding on YuvCameraViewController {
  /// Connects the view that serves capture.
  void attach(Future<YuvImage?> Function() capture) => _attach(capture);

  /// Disconnects capture if it is the current one.
  void detach(Future<YuvImage?> Function() capture) => _detach(capture);

  /// Records the geometry of the displayed frame.
  void setGeometry(Future<YuvImage?> Function() owner, YuvFrameGeometry? geometry) => _setGeometryFor(owner, geometry);
}
