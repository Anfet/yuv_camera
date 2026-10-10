import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera_screen.dart';
import 'package:yuv_camera_example/capture_result_screen.dart';
import 'package:yuv_camera_example/main.dart' as demo;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo captures a camera frame and detects faces in the result screen', (tester) async {
    await YuvFfi.initialize();
    await tester.pumpWidget(const demo.MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take photo'));
    await _pumpUntil(tester, find.byType(CameraScreen), 'camera screen should open');
    expect(find.byType(CameraScreen), findsOneWidget);

    final captureButton = find.byTooltip('Capture frame');
    await _pumpUntil(tester, captureButton, 'camera preview should become ready');
    expect(captureButton, findsOneWidget, reason: 'camera preview should become ready');

    await tester.tap(captureButton);
    await _pumpUntilGone(tester, find.byType(CameraScreen, skipOffstage: false), 'captured frame should return to the demo screen');
    expect(find.byType(CameraScreen), findsNothing, reason: 'camera frame should return to the demo screen');

    final frameFinder = find.byType(YuvFrameView);
    await _pumpUntil(tester, frameFinder, 'captured frame should be displayed');
    expect(frameFinder, findsOneWidget);
    final appState = tester.state<CaptureResultScreenState>(find.byType(CaptureResultScreen));
    final image = appState.image;
    expect(image.format, YuvPixelFormat.bgra8888, reason: 'iOS camera capture should preserve its packed BGRA format');
    expect(image.yPlane.pixelStride, 4, reason: 'each packed BGRA pixel occupies four bytes');

    // Exercise the same awaited detector path used by the Face detection button.
    await appState.detectFace();
    expect(tester.takeException(), isNull);
    expect(appState.faceBox, isNotNull, reason: 'the captured front-camera frame should contain the test operator’s face');

    await tester.tap(find.text('Detect face'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder, String reason) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  fail('Timed out: $reason');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder, String reason) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  fail('Timed out: $reason');
}
