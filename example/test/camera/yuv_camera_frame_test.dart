import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';

void main() {
  test('imports raw and upright representations lazily once', () {
    var loads = 0;
    final frame = YuvCameraFrame(
      width: 2,
      height: 2,
      format: YuvPixelFormat.bgra8888,
      orientation: YuvFrameOrientation.upright,
      timestamp: const Duration(milliseconds: 7),
      load: () {
        loads++;
        return YuvImage.bgra(2, 2);
      },
    );
    expect(loads, 0);
    expect(frame.image, same(frame.image));
    expect(loads, 1);
    expect(frame.upright(), same(frame.upright()));
    expect(loads, 1);
  });
}
