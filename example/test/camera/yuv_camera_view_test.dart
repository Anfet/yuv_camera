import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_view.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';
import 'package:yuv_camera/src/yuv_transform_view.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late CameraController camera;

  setUp(() async {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    camera = CameraController((await availableCameras()).first, ResolutionPreset.medium, enableAudio: false);
    await camera.initialize();
  });

  tearDown(() async {
    await camera.dispose();
  });

  Future<void> pumpView(WidgetTester tester, {YuvCameraViewController? controller, FutureOr<void> Function(YuvCameraFrame frame)? onFrame}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: camera, viewController: controller, onFrame: onFrame),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('onFrame is throttled and never overlaps its previous call', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await pumpView(
      tester,
      onFrame: (_) {
        calls++;
        return gate.future;
      },
    );
    await tester.pump();

    platform.emit(camera.cameraId, cameraFrame(10));
    await tester.pump();
    expect(calls, 1);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    platform.emit(camera.cameraId, cameraFrame(11));
    await tester.pump();
    expect(calls, 1);

    gate.complete();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    platform.emit(camera.cameraId, cameraFrame(12));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('capture waiting for a drawn frame completes null when the view stops', (tester) async {
    final controller = YuvCameraViewController();
    await pumpView(tester, controller: controller);
    await tester.pump();

    final capture = controller.capture();
    await tester.pumpWidget(const SizedBox());
    expect(await capture, isNull);
    controller.dispose();
  });

  testWidgets('onFrame errors are reported without stopping the source', (tester) async {
    var calls = 0;
    await pumpView(
      tester,
      onFrame: (_) {
        calls++;
        if (calls == 1) throw StateError('callback failed');
      },
    );

    platform.emit(camera.cameraId, cameraFrame(10));
    await tester.pump();
    expect(tester.takeException(), isStateError);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    platform.emit(camera.cameraId, cameraFrame(11));
    await tester.pump();
    expect(calls, 2);
    expect(platform.isStreaming(camera.cameraId), isTrue);
  });

  testWidgets('transform errors drop only that frame and keep the source running', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: YuvTransformView(
          cameraController: camera,
          transform: (frame) {
            calls++;
            if (calls == 1) throw StateError('bad frame');
            return frame.image;
          },
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    platform.emit(camera.cameraId, cameraFrame(10));
    await tester.pump();
    expect(tester.takeException(), isStateError);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    platform.emit(camera.cameraId, cameraFrame(11));
    await tester.pump();
    expect(calls, 2);
  });
}
