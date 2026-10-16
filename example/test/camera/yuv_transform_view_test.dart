import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/yuv_transform_view.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late CameraController camera;

  setUpAll(YuvFfi.initialize);

  setUp(() async {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    camera = CameraController((await availableCameras()).first, ResolutionPreset.medium, enableAudio: false);
    await camera.initialize();
  });

  tearDown(() async {
    await camera.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('transform draws one upright Android rotation without applying orientation twice', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    camera.value = camera.value.copyWith(
      description: const CameraDescription(name: 'rotated', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
    );
    YuvImage? transformed;
    YuvFrameGeometry? displayedGeometry;
    await tester.pumpWidget(
      MaterialApp(
        home: YuvTransformView(
          cameraController: camera,
          transform: (frame) => transformed = frame.upright().copy(),
          overlayBuilder: (context, geometry) {
            displayedGeometry = geometry;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await settleCamera(tester);

    platform.emit(camera.cameraId, _asymmetricFrame());
    await pumpUntil(tester, () => transformed != null && displayedGeometry != null, reason: 'the transformed upright frame and geometry');

    final pixels = transformed!.toBgraBytes();
    expect([for (var offset = 0; offset < pixels.length; offset += 4) pixels[offset]], [50, 30, 10, 60, 40, 20]);
    expect(displayedGeometry!.sourceSize, const Size(3, 2));
    expect(displayedGeometry!.orientation, YuvFrameOrientation.upright);
    expect(displayedGeometry!.orientation.rotation, YuvImageRotation.rotation0);

    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('replacement and stream error clear the previous transform overlay', (tester) async {
    var geometryReports = 0;
    Widget buildView(CameraController controller) => MaterialApp(
      home: YuvTransformView(
        cameraController: controller,
        transform: (frame) => frame.image,
        overlayBuilder: (context, geometry) {
          geometryReports++;
          return const Text('geometry overlay');
        },
      ),
    );

    await tester.pumpWidget(buildView(camera));
    await settleCamera(tester);
    platform.emit(camera.cameraId, cameraFrame(11));
    await pumpUntil(tester, () => geometryReports > 0, reason: 'initial transform geometry');
    expect(find.text('geometry overlay'), findsOneWidget);

    final replacement = CameraController(camera.description, ResolutionPreset.medium, enableAudio: false);
    await replacement.initialize();
    await tester.pumpWidget(buildView(replacement));
    await settleCamera(tester);
    expect(find.text('geometry overlay'), findsNothing);

    final reportsBeforeReplacementFrame = geometryReports;
    platform.emit(replacement.cameraId, cameraFrame(12));
    await pumpUntil(tester, () => geometryReports > reportsBeforeReplacementFrame, reason: 'replacement transform geometry');
    expect(find.text('geometry overlay'), findsOneWidget);

    platform.emitError(replacement.cameraId, StateError('transform source failed'));
    await pumpUntil(tester, () => find.textContaining('Camera error:').evaluate().isNotEmpty, reason: 'the transform stream error');
    expect(find.text('geometry overlay'), findsNothing);
    expect(find.textContaining('Camera error:'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await replacement.dispose();
  });
}

CameraImageData _asymmetricFrame() {
  const width = 2;
  const height = 3;
  const shades = [10, 20, 30, 40, 50, 60];
  final bytes = Uint8List(width * height * 4);
  for (var index = 0; index < shades.length; index++) {
    final offset = index * 4;
    bytes[offset] = shades[index];
    bytes[offset + 1] = shades[index];
    bytes[offset + 2] = shades[index];
    bytes[offset + 3] = 255;
  }
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
    width: width,
    height: height,
    planes: [CameraImagePlane(bytes: bytes, bytesPerRow: width * 4, bytesPerPixel: 4, width: width, height: height)],
  );
}
