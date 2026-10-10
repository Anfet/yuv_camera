import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';

void main() {
  test('detach keeps a newer view capture handler attached', () async {
    final controller = YuvCameraViewController();
    Future<YuvImage?> first() async => null;
    final expected = YuvImage.bgra(1, 1);
    Future<YuvImage?> second() async => expected;

    controller.attach(first);
    controller.attach(second);
    controller.detach(first);

    expect(await controller.capture(), same(expected));
    controller.dispose();
  });
}
