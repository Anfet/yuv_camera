import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';
import 'package:yuv_camera_example/faces/face_screen.dart';
import 'package:yuv_camera_example/home_screen.dart';
import 'package:yuv_camera_example/main.dart';
import 'package:yuv_camera_example/orchestrator/orchestrator_screen.dart';
import 'package:yuv_camera_example/shape_crop/shape_crop_screen.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;

  setUpAll(YuvFfi.initialize);

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  testWidgets('the home screen lists the four actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MainApp());

    for (final title in ['Shape crop', 'Open & close', 'Face detection', 'Device check']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  final screens = <String, Type>{
    'Shape crop': ShapeCropScreen,
    'Open & close': OrchestratorScreen,
    'Face detection': FaceScreen,
    'Device check': DeviceCheckScreen,
  };
  screens.forEach((title, screenType) {
    testWidgets('$title opens its screen and gives the camera back on leaving', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MainApp());
      final orchestrator = tester.widget<HomeScreen>(find.byType(HomeScreen)).orchestrator;

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await settleCamera(tester);
      expect(find.byType(screenType), findsOneWidget);

      Navigator.of(tester.element(find.byType(screenType))).pop();
      await tester.pumpAndSettle();
      await settleCamera(tester);

      expect(orchestrator.state, YuvCameraState.closed);
      expect(platform.createdCameras, platform.disposedCameras.length);
      expect(tester.takeException(), isNull);
    });
  });
}
