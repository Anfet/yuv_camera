import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Lifecycle of the camera orchestrator on the real camera and backend of the platform.
///
/// On Web the run uses Chrome's fake media device, so it checks the lifecycle and the backend, not a physical camera.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the camera opens and closes in cycles, with and without a preview', (tester) async {
    await YuvFfi.initialize();
    final orchestrator = YuvCameraOrchestrator(closeDelay: Duration.zero, lensDirection: CameraLensDirection.front);
    addTearDown(orchestrator.dispose);

    // (1) Ten bare leases: each one opens a camera, and releasing it closes the camera again.
    for (int cycle = 1; cycle <= 10; cycle++) {
      final lease = await orchestrator.acquire();
      expect(orchestrator.state, YuvCameraState.open, reason: 'cycle $cycle: state after acquire');
      expect(lease.controller.value.isInitialized, isTrue, reason: 'cycle $cycle: controller after acquire');
      lease.release();
      await _waitFor(tester, () => orchestrator.state == YuvCameraState.closed, const Duration(seconds: 5), 'cycle $cycle: the camera to close');
    }

    // (2)-(4) The preview twice: it keeps drawing frames, and removing it closes the camera.
    for (int round = 1; round <= 2; round++) {
      await tester.pumpWidget(
        MaterialApp(
          home: YuvCameraLeaseBuilder(
            orchestrator: orchestrator,
            builder: (context, controller) => YuvCameraView(cameraController: controller),
          ),
        ),
      );
      final preview = find.byType(YuvFrameView);
      await _waitFor(tester, () => preview.evaluate().isNotEmpty, const Duration(seconds: 30), 'round $round: the first frame to be drawn');

      final presenter = tester.widget<YuvFrameView>(preview).presenter;
      var drawn = 0;
      void onDrawn() => drawn++;
      presenter.addListener(onDrawn);
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 3)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      presenter.removeListener(onDrawn);
      debugPrint('[orchestrator_cycles] drawn=$drawn in ${watch.elapsed.inMilliseconds} ms');
      expect(drawn, greaterThan(10), reason: 'round $round: the preview should keep drawing camera frames');

      await tester.pumpWidget(const SizedBox());
      await _waitFor(tester, () => orchestrator.state == YuvCameraState.closed, const Duration(seconds: 5), 'round $round: the camera to close');
    }

    // (5)
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition, Duration limit, String what) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < limit) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'timed out after ${limit.inSeconds} s waiting for $what');
}
