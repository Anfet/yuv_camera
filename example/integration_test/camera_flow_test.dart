import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/main.dart' as demo;
import 'package:yuv_camera_example/shape_crop/shape_crop_screen.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo detects a face live and captures a camera frame for the shape crop', (tester) async {
    await YuvFfi.initialize();
    await tester.pumpWidget(const demo.MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Face detection'));
    await _pumpUntil(
      tester,
      () => find.text('Face detected').evaluate().isNotEmpty,
      'the test operator’s face should be detected',
      const Duration(seconds: 20),
    );
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shape crop'));
    final captureButton = find.ancestor(of: find.byTooltip('Capture frame'), matching: find.byType(IconButton));
    await _pumpUntil(
      tester,
      () => find.byType(YuvCameraView).evaluate().isNotEmpty && tester.widget<IconButton>(captureButton).onPressed != null,
      'camera preview should become ready',
      const Duration(seconds: 40),
    );
    await tester.tap(captureButton);

    final screen = find.byType(ShapeCropScreen);
    await _pumpUntil(
      tester,
      () => find.text('Step 2 of 4 · Choose shape').evaluate().isNotEmpty,
      'captured frame should move to the shape choice',
      const Duration(seconds: 20),
    );
    final image = tester.state<ShapeCropScreenState>(screen).captured;
    if (image == null) fail('The captured frame must be kept for the next steps.');
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect(image.format, YuvPixelFormat.bgra8888, reason: 'iOS camera capture should preserve its packed BGRA format');
      expect(image.yPlane.pixelStride, 4, reason: 'each packed BGRA pixel occupies four bytes');
    }
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, String reason, Duration limit) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < limit) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  }
  fail('Timed out: $reason');
}
