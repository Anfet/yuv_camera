import 'dart:js_interop';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/src/impl/yuv_camera_frame_source_web.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Web source fallback paths preserve pixels and stop delivery',
    (tester) async {
      expect(kIsWeb, isTrue);
      await YuvFfi.initialize();
      final cameras = await availableCameras();
      expect(
        cameras,
        isNotEmpty,
        reason: 'Chrome fake-media flags must expose a camera',
      );
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      final branches = <String, int>{};
      var frameCloseCount = 0;
      var lateDeliveryCount = 0;
      var bgraCopyAttempts = 0;
      final rgbaSample = Uint8List.fromList([255, 0, 0, 255]);
      final copied = await copyVideoFrameBytesForTesting(
        width: 1,
        height: 1,
        useBgra: true,
        copyBgra: (_) async {
          bgraCopyAttempts++;
          throw UnsupportedError('BGRA copyTo is unsupported');
        },
        copyRgba: (buffer) async {
          (buffer as JSUint8Array).toDart.setAll(0, rgbaSample);
        },
        onRgbaFallback: () => branches.update(
          'bgraRejected',
          (count) => count + 1,
          ifAbsent: () => 1,
        ),
      );
      expect(bgraCopyAttempts, 1);
      expect(copied.isBgra, isFalse);
      expect(copied.bytes, rgbaSample);
      final convertedSample = YuvImage.bgra(1, 1)..applyRgbaBytes(copied.bytes);
      expect(convertedSample.toBgraBytes(), [0, 0, 255, 255]);
      try {
        for (final scenario
            in <({String name, bool processor, bool visibleRect})>[
              (
                name: 'processor unavailable',
                processor: true,
                visibleRect: false,
              ),
              (name: 'BGRA rejected', processor: false, visibleRect: false),
              (
                name: 'visible rect mismatch',
                processor: false,
                visibleRect: true,
              ),
            ]) {
          final frames = <YuvCameraFrame>[];
          final errors = <Object>[];
          var stopped = false;
          final source = YuvCameraFrameSourceImpl(
            controller,
            onFrame: (frame) {
              if (stopped) lateDeliveryCount++;
              frames.add(frame);
            },
            onError: errors.add,
            forceCanvasCallbackForTesting: scenario.processor,
            forceVisibleRectMismatchForTesting: scenario.visibleRect,
            onBranchForTesting: (branch) => branches.update(
              branch,
              (count) => count + 1,
              ifAbsent: () => 1,
            ),
            onVideoFrameClosedForTesting: () => frameCloseCount++,
          );

          await source.start();
          await _waitFor(
            tester,
            () => frames.isNotEmpty || errors.isNotEmpty,
            scenario.name,
          );
          expect(
            errors,
            isEmpty,
            reason:
                '${scenario.name}; camera=${camera.name}, cameras=${cameras.map((camera) => camera.name).join(', ')}',
          );
          final frame = frames.last;
          expect(frame.width, greaterThan(0), reason: scenario.name);
          expect(frame.height, greaterThan(0), reason: scenario.name);
          final pixels = frame.image.toBgraBytes();
          expect(pixels, isNotEmpty, reason: scenario.name);
          expect(
            _distinctColors(pixels),
            greaterThan(1),
            reason: '${scenario.name}: expected distinct RGB colors',
          );
          expect(
            _hasRedBlueDifference(pixels),
            isTrue,
            reason:
                '${scenario.name}: expected a pixel with distinct red and blue channels',
          );

          final expectedBranch = switch (scenario.name) {
            'processor unavailable' => 'canvasCallback',
            'BGRA rejected' => 'bgraRejected',
            _ => 'visibleRectMismatch',
          };
          await _waitFor(
            tester,
            () => (branches[expectedBranch] ?? 0) > 0,
            '$expectedBranch branch',
          );
          stopped = true;
          await source.stopAndWait();
          source.dispose();
          final stoppedFrameCount = frames.length;
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            frames,
            hasLength(stoppedFrameCount),
            reason: '${scenario.name}: no frame may arrive after stop',
          );
        }
      } finally {
        await controller.dispose();
      }

      expect(branches['processorUnavailable'], 1);
      expect(branches['canvasCallback'], greaterThan(0));
      expect(branches['bgraRejected'], greaterThan(0));
      expect(branches['visibleRectMismatch'], greaterThan(0));
      expect(
        frameCloseCount,
        greaterThan(0),
        reason: 'VideoFrame.close must run after processing',
      );
      expect(lateDeliveryCount, 0);
      binding.reportData = {
        'processorUnavailable': branches['processorUnavailable'],
        'canvasCallback': branches['canvasCallback'],
        'bgraRejected': branches['bgraRejected'],
        'visibleRectMismatch': branches['visibleRectMismatch'],
        'frameCloseCount': frameCloseCount,
        'lateDeliveryCount': lateDeliveryCount,
      };
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what,
) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $what');
}

int _distinctColors(Uint8List bytes) {
  final colors = <int>{};
  for (var offset = 0; offset + 3 < bytes.length; offset += 4) {
    colors.add(
      (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3],
    );
    if (colors.length > 1) return colors.length;
  }
  return colors.length;
}

bool _hasRedBlueDifference(Uint8List bytes) {
  for (var offset = 0; offset + 3 < bytes.length; offset += 4) {
    if (bytes[offset] != bytes[offset + 2]) return true;
  }
  return false;
}
