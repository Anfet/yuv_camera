import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fake Web camera delivers a non-empty frame and stops cleanly', (tester) async {
    expect(kIsWeb, isTrue);
    final cameras = await availableCameras();
    expect(cameras, isNotEmpty, reason: 'Chrome fake-media flags must expose a camera');
    final camera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    addTearDown(controller.dispose);
    await controller.initialize();

    final frames = <YuvCameraFrame>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: (error) => throw StateError('$error'));
    addTearDown(source.dispose);
    await source.start();
    await _waitFor(tester, () => frames.isNotEmpty);
    final frame = frames.last;
    expect(frame.width, greaterThan(0));
    expect(frame.height, greaterThan(0));
    expect(frame.image.toBgraBytes().any((byte) => byte != 0), isTrue);

    source.dispose();
    final count = frames.length;
    await tester.pump(const Duration(milliseconds: 250));
    expect(frames, hasLength(count));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'camera did not deliver a frame');
}
