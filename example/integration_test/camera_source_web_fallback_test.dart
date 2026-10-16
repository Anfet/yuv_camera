import 'dart:js_interop';
import 'dart:collection';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;
import 'package:yuv_camera/src/impl/yuv_camera_frame_source_web.dart';
import 'package:yuv_camera/src/web_frame_copy.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web source fallback paths preserve pixels and stop delivery', (tester) async {
    expect(kIsWeb, isTrue);
    await _verifyCopyModes();
    await YuvFfi.initialize();
    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'Chrome fake-media flags must expose a camera');
    final camera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();

    final branches = <String, int>{};
    var frameCloseCount = 0;
    final closedFrames = HashMap<Object, int>.identity();
    var lateDeliveryCount = 0;
    var bgraCopyAttempts = 0;
    var copyProbeCount = 0;
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
        return <web.PlaneLayout>[web.PlaneLayout(offset: 0, stride: 4)].toJS;
      },
      onRgbaFallback: () => branches.update('bgraRejected', (count) => count + 1, ifAbsent: () => 1),
    );
    expect(bgraCopyAttempts, 1);
    expect(copied.isBgra, isFalse);
    expect(copied.bytes, rgbaSample);
    final convertedSample = YuvImage.bgra(1, 1)..applyRgbaBytes(copied.bytes);
    expect(convertedSample.toBgraBytes(), [0, 0, 255, 255]);
    try {
      for (final scenario in <({String name, bool processor, bool visibleRect})>[
        (name: 'processor unavailable', processor: true, visibleRect: false),
        (name: 'BGRA rejected', processor: false, visibleRect: false),
        (name: 'visible rect mismatch', processor: false, visibleRect: true),
      ]) {
        final frames = <YuvCameraFrame>[];
        final errors = <Object>[];
        Uint8List? canvasRgba;
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
          onBranchForTesting: (branch) => branches.update(branch, (count) => count + 1, ifAbsent: () => 1),
          onVideoFrameClosedForTesting: (frame) {
            frameCloseCount++;
            closedFrames.update(frame, (count) => count + 1, ifAbsent: () => 1);
          },
          onCopyProbeForTesting: () => copyProbeCount++,
          onRgbaPixelsForTesting: (rgba) => canvasRgba = Uint8List.fromList(rgba),
        );

        await source.start();
        await _waitFor(tester, () => frames.isNotEmpty || errors.isNotEmpty, scenario.name);
        expect(errors, isEmpty, reason: '${scenario.name}; camera=${camera.name}, cameras=${cameras.map((camera) => camera.name).join(', ')}');
        final frame = frames.last;
        expect(frame.width, greaterThan(0), reason: scenario.name);
        expect(frame.height, greaterThan(0), reason: scenario.name);
        final pixels = frame.image.toBgraBytes();
        final expectedRgba = canvasRgba ?? (throw StateError('${scenario.name}: canvas RGBA sample was not captured'));
        expect(_hasRedBlueDifference(expectedRgba), isTrue, reason: '${scenario.name}: canvas fixture needs distinct red and blue channels');
        expect(pixels, orderedEquals(_rgbaToBgra(expectedRgba)), reason: '${scenario.name}: delivered pixels must match the RGBA-to-BGRA oracle');
        expect(pixels, isNotEmpty, reason: scenario.name);
        expect(_distinctColors(pixels), greaterThan(1), reason: '${scenario.name}: expected distinct RGB colors');
        expect(_hasRedBlueDifference(pixels), isTrue, reason: '${scenario.name}: expected a pixel with distinct red and blue channels');

        final expectedBranch = switch (scenario.name) {
          'processor unavailable' => 'canvasCallback',
          'BGRA rejected' => 'bgraRejected',
          _ => 'visibleRectMismatch',
        };
        await _waitFor(tester, () => (branches[expectedBranch] ?? 0) > 0, '$expectedBranch branch');
        stopped = true;
        await source.stopAndWait();
        source.dispose();
        final stoppedFrameCount = frames.length;
        await tester.pump(const Duration(milliseconds: 300));
        expect(frames, hasLength(stoppedFrameCount), reason: '${scenario.name}: no frame may arrive after stop');
      }
    } finally {
      await controller.dispose();
    }

    expect(branches['processorUnavailable'], 1);
    expect(branches['canvasCallback'], greaterThan(0));
    expect(branches['bgraRejected'], greaterThan(0));
    expect(branches['visibleRectMismatch'], greaterThan(0));
    expect(copyProbeCount, 3, reason: 'format capability must be checked once for each source session');
    expect(frameCloseCount, greaterThanOrEqualTo(5), reason: 'each consumed frame and temporary probe frame must close');
    expect(closedFrames, isNotEmpty);
    expect(closedFrames.values.every((count) => count == 1), isTrue, reason: 'each VideoFrame identity must close exactly once');
    expect(closedFrames.length, frameCloseCount);
    expect(lateDeliveryCount, 0);
    binding.reportData = {
      'processorUnavailable': branches['processorUnavailable'],
      'canvasCallback': branches['canvasCallback'],
      'bgraRejected': branches['bgraRejected'],
      'visibleRectMismatch': branches['visibleRectMismatch'],
      'frameCloseCount': frameCloseCount,
      'uniqueClosedFrames': closedFrames.length,
      'exactlyOnceClosedFrames': closedFrames.values.where((count) => count == 1).length,
      'lateDeliveryCount': lateDeliveryCount,
      'copyProbeCount': copyProbeCount,
    };
  }, timeout: const Timeout(Duration(seconds: 90)));
}

Future<void> _verifyCopyModes() async {
  final rgba = Uint8List.fromList([13, 71, 203, 255, 229, 41, 97, 255]);
  final bgra = _rgbaToBgra(rgba);
  final tight = <web.PlaneLayout>[web.PlaneLayout(offset: 0, stride: 8)].toJS;
  final planar = <web.PlaneLayout>[web.PlaneLayout(offset: 0, stride: 2), web.PlaneLayout(offset: 2, stride: 2)].toJS;

  expect(
    await probeWebFrameCopyForTesting(width: 2, height: 1, rgbaSample: rgba, copyBgra: _copyOutput(bgra, tight), copyRgba: _unsupportedCopy),
    WebFrameCopyMode.bgra,
    reason: 'valid BGRA bytes and a tight layout select BGRA',
  );
  expect(
    await probeWebFrameCopyForTesting(width: 2, height: 1, rgbaSample: rgba, copyBgra: _unsupportedCopy, copyRgba: _copyOutput(rgba, tight)),
    WebFrameCopyMode.rgba,
    reason: 'a rejected BGRA request falls back to verified RGBA',
  );
  expect(
    await probeWebFrameCopyForTesting(
      width: 2,
      height: 1,
      rgbaSample: rgba,
      copyBgra: _copyOutput(bgra, planar),
      copyRgba: _copyOutput(rgba, planar),
    ),
    WebFrameCopyMode.canvas,
    reason: 'a planar result cannot be imported by the tight pixel reader',
  );
  expect(
    await probeWebFrameCopyForTesting(width: 2, height: 1, rgbaSample: rgba, copyBgra: _copyOutput(rgba, tight), copyRgba: _copyOutput(rgba, tight)),
    WebFrameCopyMode.rgba,
    reason: 'swapped channels in a tight BGRA result are detected by the sample',
  );
  expect(
    await probeWebFrameCopyForTesting(width: 2, height: 1, rgbaSample: rgba, copyBgra: _unsupportedCopy, copyRgba: _unsupportedCopy),
    WebFrameCopyMode.canvas,
    reason: 'when both format requests fail, the source uses canvas',
  );
  await expectLater(
    copyVideoFrameBytesForTesting(width: 2, height: 1, useBgra: true, copyBgra: _copyOutput(bgra, planar), copyRgba: _copyOutput(rgba, tight)),
    throwsFormatException,
    reason: 'a non-tight real-frame layout must reach canvas, not retry another import format',
  );
}

WebFrameCopy _copyOutput(Uint8List bytes, JSArray<web.PlaneLayout> layout) => (buffer) async {
  (buffer as JSUint8Array).toDart.setAll(0, bytes);
  return layout;
};

Future<JSArray<web.PlaneLayout>> _unsupportedCopy(web.AllowSharedBufferSource _) =>
    Future.error(UnsupportedError('VideoFrame.copyTo format is unsupported'));

Future<void> _waitFor(WidgetTester tester, bool Function() condition, String what) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $what');
}

int _distinctColors(Uint8List bytes) {
  final colors = <int>{};
  for (var offset = 0; offset + 3 < bytes.length; offset += 4) {
    colors.add((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]);
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

Uint8List _rgbaToBgra(Uint8List rgba) {
  final bgra = Uint8List.fromList(rgba);
  for (var offset = 0; offset + 3 < bgra.length; offset += 4) {
    final red = bgra[offset];
    bgra[offset] = bgra[offset + 2];
    bgra[offset + 2] = red;
  }
  return bgra;
}
