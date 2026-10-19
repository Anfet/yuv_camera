import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Where the smoke writes the captured frame as PNG, if set.
const String _outDir = String.fromEnvironment('SMOKE_OUT');

/// Real desktop capture keeps the same preview drawing, then releases the camera.
///
/// Needs a desktop with a camera. Run through the drive wrapper; see tool/test/README.md.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop capture keeps the preview drawing and releases the camera', (tester) async {
    await YuvFfi.initialize();
    final orchestrator = YuvCameraOrchestrator(
      lensDirection: CameraLensDirection.front,
      resolution: ResolutionPreset.medium,
      fps: 30,
      closeDelay: Duration.zero,
    );
    final viewController = YuvCameraViewController();
    var presented = 0;
    var baseline = 0;
    var stage = 'open and first presented frame';
    Object? scenarioError;
    StackTrace? scenarioStack;
    Object? cleanupError;
    StackTrace? cleanupStack;

    void checkCamera() {
      if (orchestrator.error case final error?) Error.throwWithStackTrace(error, StackTrace.current);
      if (orchestrator.controller?.value.errorDescription case final error?) fail('Camera error: $error');
      if (tester.takeException() case final error?) Error.throwWithStackTrace(error, StackTrace.current);
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 240,
                child: YuvCameraLeaseBuilder(
                  orchestrator: orchestrator,
                  builder: (context, controller) =>
                      YuvCameraView(cameraController: controller, viewController: viewController, onFramePresented: (_) => presented++),
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () {
          checkCamera();
          return presented > 0 && viewController.geometry.value != null;
        },
        const Duration(seconds: 30),
        stage,
      );
      final camera = orchestrator.controller;
      if (camera == null) fail('The presented frame must belong to an open camera');
      final previewState = tester.state(find.byType(YuvCameraView));

      stage = 'progress before capture';
      baseline = presented;
      await _pumpUntil(
        tester,
        () {
          checkCamera();
          return presented > baseline;
        },
        const Duration(seconds: 30),
        stage,
      );
      expect(orchestrator.state, YuvCameraState.open);
      expect(identical(orchestrator.controller, camera), isTrue);
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.currentSize + cache.liveImageCount + cache.pendingImageCount, 0, reason: 'preview frames must not pile up in ImageCache');

      stage = 'capture with the preview mounted';
      final geometry = viewController.geometry.value;
      if (geometry == null) fail('The camera view must have geometry before capture');
      final visible = geometry.visibleSourceRect.size;
      final expected = geometry.orientation.rotation.swapSize ? visible.flipped : visible;
      YuvImage? result;
      Object? captureError;
      StackTrace? captureStack;
      var captureCompleted = false;
      // Observe errors immediately while pumping the paints needed to complete capture.
      viewController.capture().then<void>(
        (image) {
          result = image;
          captureCompleted = true;
        },
        onError: (Object error, StackTrace stack) {
          captureError = error;
          captureStack = stack;
          captureCompleted = true;
        },
      );
      await _pumpUntil(
        tester,
        () {
          checkCamera();
          if (captureError case final error?) Error.throwWithStackTrace(error, captureStack ?? StackTrace.current);
          return captureCompleted;
        },
        const Duration(seconds: 30),
        stage,
      );
      final captured = result;
      if (captured == null) fail('Capture returned no frame');
      expect(viewController.geometry.value, geometry, reason: 'capture must use unchanged preview geometry');
      expect(orchestrator.state, YuvCameraState.open);
      expect(identical(orchestrator.controller, camera), isTrue);
      expect(previewState.mounted, isTrue);
      expect(tester.state(find.byType(YuvCameraView)), same(previewState));

      stage = 'progress after capture completed';
      // A frame that completed capture cannot also satisfy post-capture progress.
      baseline = presented;
      await _pumpUntil(
        tester,
        () {
          checkCamera();
          return presented > baseline;
        },
        const Duration(seconds: 30),
        stage,
      );
      expect(orchestrator.state, YuvCameraState.open);
      expect(identical(orchestrator.controller, camera), isTrue);
      expect(previewState.mounted, isTrue);

      stage = 'captured content';
      expect(captured.format, YuvPixelFormat.bgra8888);
      final capturedBgra = captured.toBgraBytes();
      expect((captured.width - expected.width).abs(), lessThanOrEqualTo(2), reason: 'captured width should match the visible source');
      expect((captured.height - expected.height).abs(), lessThanOrEqualTo(2), reason: 'captured height should match the visible source');
      expect(_distinctRgb(capturedBgra), greaterThan(1), reason: 'the captured frame should not be a flat or empty buffer');
      expect(cache.currentSize + cache.liveImageCount + cache.pendingImageCount, 0);
      if (_outDir.isNotEmpty) {
        _writePng('$_outDir/view01b_captured.png', captured.width, captured.height, _bgraToRgba(capturedBgra));
      }

      stage = 'natural close after unmount';
      await tester.pumpWidget(const SizedBox());
      await _pumpUntil(
        tester,
        () {
          checkCamera();
          return orchestrator.state == YuvCameraState.closed && orchestrator.controller == null;
        },
        const Duration(seconds: 5),
        stage,
      );
    } catch (error, stack) {
      scenarioError = error;
      scenarioStack = stack;
      binding.reportData = {
        'stage': stage,
        'state': orchestrator.state.name,
        'cameraError': '${orchestrator.error}',
        'baseline': baseline,
        'presented': presented,
      };
      _report('[view01b_smoke] FAIL $stage: $error; state=${orchestrator.state.name}, error=${orchestrator.error}, presented=$baseline->$presented');
    } finally {
      try {
        await tester.pumpWidget(const SizedBox());
      } catch (error, stack) {
        cleanupError = error;
        cleanupStack = stack;
        _report('[view01b_smoke] cleanup unmount: $error');
      }
      try {
        await orchestrator.dispose().timeout(const Duration(seconds: 10));
      } catch (error, stack) {
        cleanupError ??= error;
        cleanupStack ??= stack;
        _report('[view01b_smoke] cleanup camera dispose: $error');
      }
      try {
        viewController.dispose();
      } catch (error, stack) {
        cleanupError ??= error;
        cleanupStack ??= stack;
        _report('[view01b_smoke] cleanup view controller dispose: $error');
      }
    }
    if (scenarioError case final error?) Error.throwWithStackTrace(error, scenarioStack ?? StackTrace.current);
    if (cleanupError case final error?) Error.throwWithStackTrace(error, cleanupStack ?? StackTrace.current);
    _report('[view01b_smoke] PASS capture, post-capture progress and camera close');
  }, timeout: const Timeout(Duration(seconds: 180)));
}

/// Logs [line] and optionally saves it without hiding a scenario or cleanup error.
void _report(String line) {
  developer.log(line, name: 'view01b_smoke');
  if (_outDir.isNotEmpty) {
    try {
      File('$_outDir/view01b_smoke.log').writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (error, stack) {
      developer.log('Could not save smoke log', name: 'view01b_smoke', error: error, stackTrace: stack);
    }
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, Duration timeout, String reason) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= timeout) fail('Timed out: $reason');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Uint8List _bgraToRgba(Uint8List bgra) {
  final rgba = Uint8List(bgra.length);
  for (var i = 0; i < bgra.length; i += 4) {
    rgba[i] = bgra[i + 2];
    rgba[i + 1] = bgra[i + 1];
    rgba[i + 2] = bgra[i];
    rgba[i + 3] = bgra[i + 3];
  }
  return rgba;
}

int _distinctRgb(Uint8List bgra) {
  final colors = <int>{};
  for (var i = 0; i < bgra.length; i += 4) {
    colors.add(bgra[i] | bgra[i + 1] << 8 | bgra[i + 2] << 16);
    if (colors.length > 1) break;
  }
  return colors.length;
}

void _writePng(String path, int width, int height, Uint8List rgba) {
  final image = img.Image.fromBytes(width: width, height: height, bytes: rgba.buffer, numChannels: 4);
  File(path).writeAsBytesSync(img.encodePng(image));
}
