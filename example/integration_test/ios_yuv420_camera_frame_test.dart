import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports the iOS two-plane yuv420 NV12 fixture', (tester) async {
    await YuvFfi.initialize();
    // ignore: deprecated_member_use
    final cameraImage = CameraImage.fromPlatformData(<dynamic, dynamic>{
      'format': 875704438,
      'width': 3,
      'height': 3,
      'planes': <Map<dynamic, dynamic>>[
        <dynamic, dynamic>{
          'bytes': Uint8List.fromList([
            82,
            82,
            82,
            0xee,
            82,
            82,
            82,
            0xee,
            82,
            82,
            82,
          ]),
          'bytesPerRow': 4,
          'bytesPerPixel': null,
          'width': 3,
          'height': 3,
        },
        <dynamic, dynamic>{
          'bytes': Uint8List.fromList([90, 240, 54, 34, 0xee, 90, 240, 54, 34]),
          'bytesPerRow': 5,
          'bytesPerPixel': null,
          'width': 2,
          'height': 2,
        },
      ],
    });

    final image = importCameraImage(cameraImage);
    expect(image.format, YuvPixelFormat.nv12);
    expect(image.uPlane.pixelStride, 2);
    expect(image.uPlane.rowStride, 5);
    expect(image.toBgraBytes().take(4), [0, 1, 255, 255]);
  });

  const runIosCamera = bool.fromEnvironment('YUV_IOS_CAMERA_RUNTIME');
  const requestedLens = String.fromEnvironment(
    'YUV_IOS_CAMERA_LENS',
    defaultValue: 'back',
  );
  testWidgets(
    'real iOS $requestedLens camera provides YUV420 frames to preview and capture',
    (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      expect(requestedLens, anyOf('front', 'back'));
      await YuvFfi.initialize();
      final cameras = await availableCameras();
      final lens = requestedLens == 'front'
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final camera = cameras
          .where((candidate) => candidate.lensDirection == lens)
          .firstOrNull;
      expect(
        camera,
        isNotNull,
        reason:
            'The requested $requestedLens camera must be present on this device.',
      );

      final controller = CameraController(
        camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      final viewController = YuvCameraViewController();
      var frameCount = 0;
      var presentedCount = 0;
      final frameFormats = <YuvPixelFormat>[];
      try {
        await controller.initialize();
        expect(controller.value.isInitialized, isTrue);
        debugPrint('[ios_yuv420] $requestedLens: initialized');
        // Right after initialization a real device shows flicker and distorted frames.
        await tester.pump(const Duration(milliseconds: 1500));
        final picture = await controller.takePicture();
        debugPrint('[ios_yuv420] $requestedLens: still captured');
        expect(
          picture.path,
          isNotEmpty,
          reason: 'A still capture should complete before preview starts.',
        );

        CameraImage? rawFrame;
        await controller.startImageStream((frame) => rawFrame ??= frame);
        await _waitFor(tester, () => rawFrame != null);
        debugPrint('[ios_yuv420] $requestedLens: raw frame received');
        expect(rawFrame!.format.group, ImageFormatGroup.yuv420);
        expect(rawFrame!.planes, hasLength(2));
        await controller.stopImageStream();
        debugPrint('[ios_yuv420] $requestedLens: stream stopped');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 240,
                child: YuvCameraView(
                  cameraController: controller,
                  viewController: viewController,
                  onFrameInterval: Duration.zero,
                  onFrame: (frame) {
                    frameCount++;
                    frameFormats.add(frame.format);
                  },
                  onFramePresented: (_) => presentedCount++,
                ),
              ),
            ),
          ),
        );
        debugPrint('[ios_yuv420] $requestedLens: preview pumped');
        await _waitFor(tester, () => frameCount > 0 && presentedCount > 0);
        debugPrint('[ios_yuv420] $requestedLens: frames presented');
        expect(frameFormats, contains(YuvPixelFormat.nv12));
        // The capture completes on the next presented frame: keep pumping frames while waiting.
        var captureDone = false;
        final captureFuture = viewController.capture().whenComplete(
          () => captureDone = true,
        );
        await _waitFor(tester, () => captureDone);
        final previewCapture = await captureFuture;
        debugPrint('[ios_yuv420] $requestedLens: captured');
        expect(previewCapture, isNotNull);
        expect(previewCapture!.format, YuvPixelFormat.nv12);
      } finally {
        debugPrint('[ios_yuv420] $requestedLens: cleanup');
        await tester.pumpWidget(const SizedBox());
        viewController.dispose();
        await controller.dispose();
        debugPrint('[ios_yuv420] $requestedLens: disposed');
      }
    },
    skip: !runIosCamera,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 300 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    condition(),
    isTrue,
    reason: 'The real camera did not produce a preview frame.',
  );
}
