import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Lifecycle of the camera orchestrator on the real camera and backend of the platform.
///
/// On Web the source depends on the browser flags supplied by the runner; the real-camera gate uses a physical camera.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = false);
  tearDown(binding.platformDispatcher.clearSemanticsEnabledTestValue);

  testWidgets('the camera opens and closes in cycles, with and without a preview', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await YuvFfi.initialize();
    final orchestrator = YuvCameraOrchestrator(closeDelay: Duration.zero, lensDirection: CameraLensDirection.front);
    Object? scenarioError;
    StackTrace? scenarioStack;
    Object? cleanupError;
    StackTrace? cleanupStack;
    var failureStage = 'first bare lease acquire';
    final previewDrawCounts = <int>[];
    List<int>? sharedPreviewDrawCounts;
    int? survivingPreviewDrawCount;
    var closedAfterFinalPreview = false;

    try {
      // (1) Ten bare leases: each one opens a camera, and releasing it closes the camera again.
      for (int cycle = 1; cycle <= 10; cycle++) {
        failureStage = 'bare lease cycle $cycle acquire';
        debugPrint('[orchestrator_cycles] cycle $cycle: acquire started');
        final acquiring = orchestrator.acquire();
        await _waitFor(
          tester,
          () => orchestrator.state == YuvCameraState.open || orchestrator.error != null,
          const Duration(seconds: 30),
          'cycle $cycle: the camera to open',
        );
        debugPrint('[orchestrator_cycles] cycle $cycle: state=${orchestrator.state.name}, error=${orchestrator.error}');
        final lease = await acquiring;
        failureStage = 'bare lease cycle $cycle release';
        expect(orchestrator.state, YuvCameraState.open, reason: 'cycle $cycle: state after acquire');
        expect(lease.controller.value.isInitialized, isTrue, reason: 'cycle $cycle: controller after acquire');
        await _settle(tester);
        lease.release();
        await _waitFor(tester, () => orchestrator.state == YuvCameraState.closed, const Duration(seconds: 5), 'cycle $cycle: the camera to close');
        await Future<void>.delayed(const Duration(seconds: 1));
        debugPrint('[orchestrator_cycles] cycle $cycle: closed');
      }

      // (2)-(4) The preview twice: it keeps drawing frames, and removing it closes the camera.
      for (int round = 1; round <= 2; round++) {
        var drawn = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: YuvCameraLeaseBuilder(
              orchestrator: orchestrator,
              builder: (context, controller) => YuvCameraView(cameraController: controller, onFramePresented: (_) => drawn++),
            ),
          ),
        );
        final preview = find.byType(YuvFrameView);
        await _waitFor(tester, () => preview.evaluate().isNotEmpty, const Duration(seconds: 30), 'round $round: the preview widget');

        await _waitFor(tester, () => drawn > 0, const Duration(seconds: 30), 'round $round: the first presented frame');
        await _settle(tester);
        drawn = 0;
        final watch = Stopwatch()..start();
        while (watch.elapsed < const Duration(seconds: 3)) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        debugPrint('[orchestrator_cycles] drawn=$drawn in ${watch.elapsed.inMilliseconds} ms');
        previewDrawCounts.add(drawn);
        expect(drawn, greaterThan(10), reason: 'round $round: the preview should keep drawing camera frames');

        await tester.pumpWidget(const SizedBox());
        await _waitFor(tester, () => orchestrator.state == YuvCameraState.closed, const Duration(seconds: 5), 'round $round: the camera to close');
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // (5) Two previews share one controller and one platform stream; either preview can go away independently.
      var showFirst = true;
      var firstPresented = 0;
      var secondPresented = 0;
      CameraController? firstController;
      CameraController? secondController;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Row(
              children: [
                if (showFirst)
                  Expanded(
                    child: YuvCameraLeaseBuilder(
                      orchestrator: orchestrator,
                      builder: (context, controller) {
                        firstController = controller;
                        return YuvCameraView(cameraController: controller, onFramePresented: (_) => firstPresented++);
                      },
                    ),
                  ),
                Expanded(
                  child: YuvCameraLeaseBuilder(
                    key: const ValueKey('second-preview'),
                    orchestrator: orchestrator,
                    builder: (context, controller) {
                      secondController = controller;
                      return YuvCameraView(cameraController: controller, onFramePresented: (_) => secondPresented++);
                    },
                  ),
                ),
                TextButton(onPressed: () => setState(() => showFirst = false), child: const Text('Remove first')),
              ],
            ),
          ),
        ),
      );
      await _waitFor(tester, () => firstPresented > 0 && secondPresented > 0, const Duration(seconds: 30), 'both shared previews to present a frame');
      expect(identical(firstController, secondController), isTrue, reason: 'both previews must lease the same controller');
      final sharedController = orchestrator.controller;
      expect(identical(firstController, sharedController), isTrue);

      await _settle(tester);
      firstPresented = 0;
      secondPresented = 0;
      var watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 3)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(firstPresented, greaterThan(10), reason: 'the first preview should keep presenting camera frames');
      expect(secondPresented, greaterThan(10), reason: 'the second preview should keep presenting camera frames');
      sharedPreviewDrawCounts = [firstPresented, secondPresented];

      await tester.tap(find.text('Remove first'));
      await tester.pump();
      expect(identical(orchestrator.controller, sharedController), isTrue, reason: 'removing one lease must keep the same controller');
      secondPresented = 0;
      watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 3)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      survivingPreviewDrawCount = secondPresented;
      expect(secondPresented, greaterThan(10), reason: 'the surviving preview should continue presenting after removal');

      await tester.pumpWidget(const SizedBox());
      await _waitFor(
        tester,
        () => orchestrator.state == YuvCameraState.closed,
        const Duration(seconds: 5),
        'the shared camera to close after the last preview',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      closedAfterFinalPreview = orchestrator.state == YuvCameraState.closed;

      // (6)
      expect(tester.takeException(), isNull);
    } catch (error, stack) {
      scenarioError = error;
      scenarioStack = stack;
      binding.reportData = {'failureStage': failureStage, 'error': '$error', 'orchestratorState': orchestrator.state.name};
    } finally {
      try {
        await tester.pumpWidget(const SizedBox());
      } catch (error, stack) {
        cleanupError = error;
        cleanupStack = stack;
      }
      try {
        await orchestrator.dispose();
      } catch (error, stack) {
        cleanupError ??= error;
        cleanupStack ??= stack;
      }
    }

    if (scenarioError != null) {
      Error.throwWithStackTrace(scenarioError, scenarioStack!);
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStack!);
    }
    binding.reportData = {
      'bareLeaseCycles': 10,
      'singlePreviewDrawCounts': previewDrawCounts,
      'sharedPreviewDrawCounts': sharedPreviewDrawCounts,
      'survivingPreviewDrawCount': survivingPreviewDrawCount,
      'closedAfterFinalPreview': closedAfterFinalPreview,
    };
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition, Duration limit, String what) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < limit) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'timed out after ${limit.inSeconds} s waiting for $what');
}

/// Lets the camera settle after it opens: right after initialization a real
/// device shows flicker and distorted frames.
Future<void> _settle(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(milliseconds: 1500)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
