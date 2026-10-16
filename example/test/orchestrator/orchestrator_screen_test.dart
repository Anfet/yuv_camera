import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/orchestrator/orchestrator_screen.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late YuvCameraOrchestrator orchestrator;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    orchestrator = YuvCameraOrchestrator();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: OrchestratorScreen(orchestrator: orchestrator, cameraSettleDelay: Duration.zero)));
  }

  testWidgets('Open opens the camera and Close closes it', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Open'));
    await tester.pump();
    await settleCamera(tester);
    expect(orchestrator.state, YuvCameraState.open);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await settleCamera(tester);
    expect(orchestrator.state, YuvCameraState.closed);
  });

  testWidgets('ten open/close cycles finish without errors and release every camera', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Open/close ×10'));
    await tester.pump();
    final complete = () => find.textContaining('10 cycles done').evaluate().isNotEmpty;
    for (int i = 0; i < 400 && !complete(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(complete(), isTrue, reason: 'timed out waiting for ten cycles');
    await settleCamera(tester);

    expect(find.textContaining('10 cycles done · 0 errors'), findsOneWidget);
    expect(platform.createdCameras, 10);
    expect(platform.disposedCameras.length, platform.createdCameras);
  });
}
