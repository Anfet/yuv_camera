import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A handle for observing a [YuvCameraView] and capturing its next drawn frame.
class YuvCameraViewController extends ChangeNotifier {
  final ValueNotifier<YuvFrameGeometry?> _geometry = ValueNotifier(null);
  Future<YuvImage?> Function()? _capture;

  /// Geometry used for the currently displayed frame.
  ValueListenable<YuvFrameGeometry?> get geometry => _geometry;

  /// Returns the next frame that is actually drawn, cropped to what is visible.
  Future<YuvImage?> capture() => _capture?.call() ?? Future<YuvImage?>.value(null);

  void attach(Future<YuvImage?> Function() capture) => _capture = capture;

  void detach(Future<YuvImage?> Function() capture) {
    if (_capture == capture) _capture = null;
  }

  void setGeometry(YuvFrameGeometry geometry) => _setGeometry(geometry);

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
