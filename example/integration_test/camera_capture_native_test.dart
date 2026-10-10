import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_view.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';

import '../test/support/fake_camera.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // onFrame never completes here, so a finished capture also shows that drawing does not wait for onFrame.
  testWidgets('capture equals the geometry applied to its drawn frame while onFrame is still running', (tester) async {
    await YuvFfi.initialize();
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final camera = CameraController((await availableCameras()).first, ResolutionPreset.medium, enableAudio: false);
    await camera.initialize();
    addTearDown(camera.dispose);
    final controller = YuvCameraViewController();
    addTearDown(controller.dispose);
    YuvCameraFrame? drawn;
    final pendingOnFrame = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(
          cameraController: camera,
          viewController: controller,
          onFrame: (frame) {
            drawn ??= frame;
            return pendingOnFrame.future;
          },
        ),
      ),
    );
    await tester.pump();
    final capture = controller.capture();
    platform.emit(camera.cameraId, cameraFrame(77));
    await _pumpUntil(tester, () => drawn != null && controller.geometry.value != null);
    final image = await capture;
    final frame = drawn!;
    final expected = controller.geometry.value!.apply(frame.image);
    expect(image!.toBgraBytes(), orderedEquals(expected.toBgraBytes()));
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 120 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(condition(), isTrue, reason: 'camera frame was not drawn');
}
