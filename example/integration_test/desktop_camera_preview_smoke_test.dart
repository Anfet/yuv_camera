import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera_screen.dart';
import 'package:yuv_camera_example/capture_result_screen.dart';
import 'package:yuv_camera_example/main.dart' as demo;

/// Where the smoke writes the drawn and the captured frame as PNG, if set.
const String _outDir = String.fromEnvironment('SMOKE_OUT');

/// Desktop camera smoke: the demo opens
/// `CameraScreen`, the `camera_desktop` stream is shown through the preview
/// for a few seconds, and "Capture frame" returns the frame that was drawn.
///
/// Needs a desktop with a camera; not part of CI. Run from `example/`:
///   flutter test integration_test/desktop_camera_preview_smoke_test.dart -d windows --dart-define=SMOKE_OUT=`<dir>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop preview shows the camera stream and captures the drawn frame', (tester) async {
    await YuvFfi.initialize();
    await tester.pumpWidget(const demo.MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take photo'));
    final preview = find.descendant(of: find.byType(CameraScreen), matching: find.byType(YuvFrameView));
    await _pumpUntil(tester, () => preview.evaluate().isNotEmpty, 'the first camera frame should be drawn');

    final watch = Stopwatch()..start();
    var distinctDrawn = 0;
    ui.Image? last;
    final fpsReadings = <String>[];
    while (watch.elapsed < const Duration(seconds: 6)) {
      await tester.pump(const Duration(milliseconds: 16));
      final image = tester.widget<RawImage>(preview).image;
      if (image != null && (last == null || !image.isCloneOf(last))) {
        distinctDrawn++;
        last?.dispose();
        last = image.clone();
      }
      final fps = find.textContaining(' fps');
      if (fps.evaluate().isNotEmpty) {
        fpsReadings.add(tester.widget<Text>(fps).data ?? '');
      }
    }
    last?.dispose();
    final cache = PaintingBinding.instance.imageCache;
    debugPrint(
      '[view01b_smoke] drawn distinct frames in ${watch.elapsed.inMilliseconds} ms: $distinctDrawn; '
      'fps labels: ${fpsReadings.toSet().toList()}; imageCache current=${cache.currentSize} live=${cache.liveImageCount} pending=${cache.pendingImageCount}',
    );
    expect(distinctDrawn, greaterThan(10), reason: 'the preview should keep drawing new camera frames');
    expect(cache.currentSize + cache.liveImageCount + cache.pendingImageCount, 0, reason: 'preview frames must not pile up in ImageCache');

    // The frame taken by capture is the first one accepted after the tap, so
    // it is one of the next two frames drawn (one may already be in flight).
    final drawnAfterTap = <ui.Image>[];
    final beforeTap = tester.widget<RawImage>(preview).image?.clone();
    await tester.tap(find.byTooltip('Capture frame'));
    var previous = beforeTap;
    while (drawnAfterTap.length < 2 && preview.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 4));
      final image = tester.widget<RawImage>(preview).image;
      if (image != null && (previous == null || !image.isCloneOf(previous))) {
        final kept = image.clone();
        drawnAfterTap.add(kept);
        previous = kept;
      }
    }
    beforeTap?.dispose();

    await _pumpUntil(tester, () => find.byType(CameraScreen).evaluate().isEmpty, 'the captured frame should return to the demo');
    await _pumpUntil(tester, () => find.byType(YuvFrameView).evaluate().isNotEmpty, 'the captured frame should be displayed');
    final captured = tester.state<CaptureResultScreenState>(find.byType(CaptureResultScreen)).image;
    final capturedRgba = _bgraToRgba(captured.toBgraBytes());
    debugPrint('[view01b_smoke] captured: $captured');

    int? matched;
    for (var i = 0; i < drawnAfterTap.length; i++) {
      final drawn = drawnAfterTap[i];
      final data = await drawn.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (drawn.width == captured.width && drawn.height == captured.height && _equal(data!.buffer.asUint8List(), capturedRgba)) {
        matched = i;
        if (_outDir.isNotEmpty) {
          _writePng('$_outDir/view01b_drawn.png', drawn.width, drawn.height, data.buffer.asUint8List());
        }
        break;
      }
    }
    if (_outDir.isNotEmpty) {
      _writePng('$_outDir/view01b_captured.png', captured.width, captured.height, capturedRgba);
    }
    for (final image in drawnAfterTap) {
      image.dispose();
    }
    debugPrint('[view01b_smoke] captured frame equals drawn frame #$matched after the tap');
    expect(matched, isNotNull, reason: 'capture must return exactly a frame the preview drew');
    expect(captured.format, YuvPixelFormat.bgra8888);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, String reason) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Timed out: $reason');
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

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _writePng(String path, int width, int height, Uint8List rgba) {
  final image = img.Image.fromBytes(width: width, height: height, bytes: rgba.buffer, numChannels: 4);
  File(path).writeAsBytesSync(img.encodePng(image));
}
