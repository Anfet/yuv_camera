import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A handle for observing a [YuvCameraView] and capturing its next drawn frame.
class YuvCameraViewController extends ChangeNotifier {
  final ValueNotifier<YuvFrameGeometry?> _geometry = ValueNotifier(null);
  Future<YuvImage?> Function()? _capture;

  /// Geometry used for the currently displayed frame.
  ValueListenable<YuvFrameGeometry?> get geometry => _geometry;

  /// Returns the next frame that is actually drawn, cropped to what is visible.
  /// Completes with `null` if the view stops, including when its frame stream fails, before a frame is drawn.
  Future<YuvImage?> capture() => _capture?.call() ?? Future<YuvImage?>.value(null);

  void _attach(Future<YuvImage?> Function() capture) => _capture = capture;

  void _detach(Future<YuvImage?> Function() capture) {
    if (_capture == capture) _capture = null;
  }

  void _setGeometry(YuvFrameGeometry? geometry) {
    if (_geometry.value == geometry) return;
    _geometry.value = geometry;
    notifyListeners();
  }

  @override
  void dispose() {
    _capture = null;
    _geometry.dispose();
    super.dispose();
  }
}

/// Internal binding used by YuvCameraView; hidden from the package export.
extension YuvCameraViewControllerBinding on YuvCameraViewController {
  /// Connects the view that serves capture.
  void attach(Future<YuvImage?> Function() capture) => _attach(capture);

  /// Disconnects capture if it is the current one.
  void detach(Future<YuvImage?> Function() capture) => _detach(capture);

  /// Records the geometry of the displayed frame.
  void setGeometry(YuvFrameGeometry geometry) => _setGeometry(geometry);
}
