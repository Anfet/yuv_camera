import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera_screen.dart';
import 'package:yuv_camera_example/capture_result_screen.dart';
import 'package:yuv_camera_example/main.dart' as demo;

/// Where the smoke writes the captured frame as PNG, if set.
const String _outDir = String.fromEnvironment('SMOKE_OUT');

/// Desktop camera smoke: the demo opens
/// `CameraScreen`, the `camera_desktop` stream is shown through the preview
/// for a few seconds, and "Capture frame" returns a frame of the visible source.
///
/// Needs a desktop with a camera; not part of CI. Run from the package root:
///   pwsh -File tool/ci/drive.ps1 integration_test/desktop_camera_preview_smoke_test.dart windows --dart-define=SMOKE_OUT=`<dir>`
///   bash tool/ci/drive.sh integration_test/desktop_camera_preview_smoke_test.dart macos --dart-define=SMOKE_OUT=`<dir>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop preview shows the camera stream and captures the drawn frame', (tester) async {
    await YuvFfi.initialize();
    await tester.pumpWidget(const demo.MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take photo'));
    final preview = find.descendant(of: find.byType(CameraScreen), matching: find.byType(YuvFrameView));
    await _pumpUntil(tester, () => preview.evaluate().isNotEmpty, 'the first camera frame should be drawn');

    final presenter = tester.widget<YuvFrameView>(preview).presenter;
    var drawn = 0;
    void onDrawn() => drawn++;
    presenter.addListener(onDrawn);
    final watch = Stopwatch()..start();
    final fpsReadings = <String>[];
    while (watch.elapsed < const Duration(seconds: 6)) {
      await tester.pump(const Duration(milliseconds: 16));
      final fps = find.textContaining(' fps');
      if (fps.evaluate().isNotEmpty) {
        fpsReadings.add(tester.widget<Text>(fps).data ?? '');
      }
    }
    presenter.removeListener(onDrawn);
    final cache = PaintingBinding.instance.imageCache;
    debugPrint(
      '[view01b_smoke] drawn frames in ${watch.elapsed.inMilliseconds} ms: $drawn; hasShader=${presenter.hasShader}; '
      'fps labels: ${fpsReadings.toSet().toList()}; imageCache current=${cache.currentSize} live=${cache.liveImageCount} pending=${cache.pendingImageCount}',
    );
    expect(drawn, greaterThan(10), reason: 'the preview should keep drawing new camera frames');
    expect(cache.currentSize + cache.liveImageCount + cache.pendingImageCount, 0, reason: 'preview frames must not pile up in ImageCache');

    // The shader preview exposes no pixels, so the capture is checked by its
    // size against the visible part of the source and by having real content.
    // Byte equality with the drawn frame is proven by camera_capture_native_test
    // ("capture equals the geometry applied to its drawn frame").
    final cameraView = find.descendant(of: find.byType(CameraScreen), matching: find.byType(YuvCameraView));
    final geometry = tester.widget<YuvCameraView>(cameraView).viewController?.geometry.value;
    if (geometry == null) fail('the camera view should have a geometry before capture');
    final visible = geometry.visibleSourceRect.size;
    final expected = geometry.orientation.rotation.swapSize ? visible.flipped : visible;
    await tester.tap(find.byTooltip('Capture frame'));

    await _pumpUntil(tester, () => find.byType(CameraScreen).evaluate().isEmpty, 'the captured frame should return to the demo');
    await _pumpUntil(tester, () => find.byType(YuvFrameView).evaluate().isNotEmpty, 'the captured frame should be displayed');
    final captured = tester.state<CaptureResultScreenState>(find.byType(CaptureResultScreen)).image;
    final capturedBgra = captured.toBgraBytes();
    debugPrint('[view01b_smoke] captured: $captured; expected visible ${expected.width.round()}x${expected.height.round()}');

    if (_outDir.isNotEmpty) {
      _writePng('$_outDir/view01b_captured.png', captured.width, captured.height, _bgraToRgba(capturedBgra));
    }
    expect((captured.width - expected.width).abs(), lessThanOrEqualTo(2), reason: 'captured width should match the visible source');
    expect((captured.height - expected.height).abs(), lessThanOrEqualTo(2), reason: 'captured height should match the visible source');
    expect(_distinctRgb(capturedBgra), greaterThan(1), reason: 'the captured frame should not be a flat or empty buffer');
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
