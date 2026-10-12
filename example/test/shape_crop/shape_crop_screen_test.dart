import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/shape_crop/shape_crop_screen.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late YuvCameraOrchestrator orchestrator;

  setUpAll(YuvFfi.initialize);

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    orchestrator = YuvCameraOrchestrator();
  });

  Future<void> capture(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ShapeCropScreen(orchestrator: orchestrator)));
    await settleCamera(tester);
    await tester.tap(find.byTooltip('Capture frame'));
    await tester.pump();
    platform.emit(platform.listens.single, cameraFrame(40));
    await pumpUntil(tester, () => find.text('Step 2 of 4 · Choose shape').evaluate().isNotEmpty, reason: 'step 2');
    await settleCamera(tester);
  }

  Future<void> crop(WidgetTester tester, String shape) async {
    await tester.tap(find.text(shape));
    await tester.pump();
    await tester.tap(find.textContaining('Next: place the'));
    await tester.pump();
    await tester.tap(find.text('Crop'));
    await tester.pump();
  }

  testWidgets('a captured frame moves to the shape choice and the camera closes', (tester) async {
    await capture(tester);

    expect(find.text('Step 2 of 4 · Choose shape'), findsOneWidget);
    expect(tester.state<ShapeCropScreenState>(find.byType(ShapeCropScreen)).captured, isNotNull);
    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.disposedCameras, [1]);
    await settleDecodes(tester);
  });

  testWidgets('the circle result counts the pixels of the same cut made directly', (tester) async {
    await capture(tester);
    await crop(tester, 'Circle');

    final captured = tester.state<ShapeCropScreenState>(find.byType(ShapeCropScreen)).captured;
    if (captured == null) fail('The frame must be captured.');
    final expected = captured.croppedToShape(const YuvCropTarget.square(0.5), shape: YuvCropShape.ellipse).insideCount;
    expect(find.text('Step 4 of 4 · Result'), findsOneWidget);
    expect(find.text('$expected px'), findsOneWidget);
    await settleDecodes(tester);
  });

  testWidgets('another fill changes the cut image', (tester) async {
    await capture(tester);
    await crop(tester, 'Oval');
    final before = tester.widget<YuvImageWidget>(find.byType(YuvImageWidget)).image.toBgraBytes();

    await tester.tap(find.text('Magenta'));
    await tester.pump();

    final after = tester.widget<YuvImageWidget>(find.byType(YuvImageWidget)).image.toBgraBytes();
    expect(after, isNot(before));
    await settleDecodes(tester);
  });
}
