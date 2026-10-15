import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/yuv_camera.dart';

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

  testWidgets('terminal frame error drains before Retry and capture from the replacement camera', (tester) async {
    await YuvFfi.initialize();
    final physicalPlatform = CameraPlatform.instance;
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final orchestrator = YuvCameraOrchestrator(closeDelay: Duration.zero);
    final viewController = YuvCameraViewController();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: YuvCameraLeaseBuilder(
            orchestrator: orchestrator,
            builder: (context, controller) => Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: YuvCameraView(cameraController: controller, viewController: viewController),
                ),
                Expanded(child: YuvCameraView(cameraController: controller)),
              ],
            ),
          ),
        ),
      );
      await settleCamera(tester);
      expect(platform.createdCameras, 1);
      expect(platform.isStreaming(1), isTrue);
      final stopGate = platform.stopGate = Completer<void>();
      platform.emitError(1, StateError('integration frame stream failed'));
      await settleCamera(tester);
      expect(orchestrator.state, YuvCameraState.closing);
      expect(platform.disposedCameras, isEmpty);
      expect(platform.createdCameras, 1);

      stopGate.complete();
      await settleCamera(tester);
      expect(orchestrator.state, YuvCameraState.closed);
      expect(platform.disposedCameras, [1]);
      expect(platform.events, containsAllInOrder(['listen:1', 'cancel:1', 'dispose:1']));

      await tester.tap(find.text('Retry'));
      await settleCamera(tester);
      expect(orchestrator.state, YuvCameraState.open);
      expect(platform.createdCameras, 2);
      expect(platform.isStreaming(2), isTrue);
      final capture = viewController.capture();
      YuvImage? captured;
      capture.then((image) => captured = image);
      platform.emit(2, cameraFrame(63));
      await pumpUntil(tester, () => captured != null, reason: 'replacement camera capture');
      expect(shadeOfYuv(captured ?? (throw StateError('Replacement capture did not complete'))), 63);
      expect(platform.overlappingStarts, isEmpty);
    } finally {
      if (platform.stopGate case final gate? when !gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox());
      await settleCamera(tester);
      viewController.dispose();
      await orchestrator.dispose();
      CameraPlatform.instance = physicalPlatform;
    }
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 120 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(condition(), isTrue, reason: 'camera frame was not drawn');
}
