import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detaching an old view does not clear the newer owner geometry', () {
    final controller = YuvCameraViewController();
    Future<YuvImage?> first() async => null;
    Future<YuvImage?> second() async => null;
    final geometry = YuvFrameGeometry(sourceSize: const Size(2, 3), viewSize: const Size(20, 30));

    controller.attach(first);
    controller.setGeometry(first, geometry);
    controller.attach(second);
    controller.setGeometry(second, geometry);
    controller.detach(first);

    expect(controller.geometry.value, geometry);
    controller.detach(second);
    expect(controller.geometry.value, isNull);
    controller.dispose();
  });

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

  testWidgets('disposing before a deferred geometry notification drops that notification', (tester) async {
    final controller = YuvCameraViewController();
    Future<YuvImage?> owner() async => null;
    final geometry = YuvFrameGeometry(sourceSize: const Size(2, 3), viewSize: const Size(20, 30));
    var notifications = 0;
    controller.geometry.addListener(() => notifications++);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          controller.attach(owner);
          controller.setGeometry(owner, geometry);
          controller.dispose();
          return const SizedBox();
        },
      ),
    );

    expect(notifications, 0);
  });
}
