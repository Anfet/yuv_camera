import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/faces/face_screen.dart';

import '../support/fake_camera.dart';

void main() {
  testWidgets('a platform without ML Kit says so instead of detecting', (tester) async {
    CameraPlatform.instance = FakeCameraPlatform();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(MaterialApp(home: FaceScreen(orchestrator: YuvCameraOrchestrator())));
      await settleCamera(tester);

      expect(find.text('Face detection needs Android or iOS'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
