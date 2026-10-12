import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('onFrame resumes at once after the cameraController is replaced', (tester) async {
    var calls = 0;
    await pumpView(tester, onFrame: (_) => calls++);
    platform.emit(camera.cameraId, cameraFrame(10));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    platform.emit(camera.cameraId, cameraFrame(11));
    await tester.pump();
    expect(calls, 2);

    final replacement = CameraController((await availableCameras()).first, ResolutionPreset.medium, enableAudio: false);
    await replacement.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: replacement, onFrame: (_) => calls++),
      ),
    );
    await settleCamera(tester);
    platform.emit(replacement.cameraId, cameraFrame(12));
    await tester.pump();
    expect(calls, 3);

    await tester.pumpWidget(const SizedBox());
    await replacement.dispose();
  });

  testWidgets('an unsupported image format group stops the stream and shows the error', (tester) async {
    await pumpView(tester);
    platform.emit(camera.cameraId, nv21Frame());
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Camera error: Unsupported operation: Unsupported camera image format'), findsOneWidget);
    expect(platform.isStreaming(camera.cameraId), isFalse);
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
  for (final transformed in [false, true]) {
    testWidgets('${transformed ? 'transform' : 'camera'} view only reports stream errors and resumes frames on replacement', (tester) async {
      var stopped = 0;
      final shades = <int>[];
      Future<void> pumpCamera(CameraController controller) async {
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                void onStopped() => setState(() => stopped++);
                return transformed
                    ? YuvTransformView(
                        cameraController: controller,
                        onStreamStopped: onStopped,
                        transform: (frame) {
                          shades.add(shadeOfYuv(frame.image));
                          return frame.image;
                        },
                      )
                    : YuvCameraView(
                        cameraController: controller,
                        onStreamStopped: onStopped,
                        onFrame: (frame) => shades.add(shadeOfYuv(frame.image)),
                      );
              },
            ),
          ),
        );
        await settleCamera(tester);
      }

      await pumpCamera(camera);
      platform.emit(camera.cameraId, cameraFrame(10));
      await tester.pump();
      expect(shades, [10]);
      final replacement = CameraController(camera.description, ResolutionPreset.medium, enableAudio: false);
      await replacement.initialize();
      await pumpCamera(replacement);
      expect(stopped, 0);
      platform.emit(camera.cameraId, cameraFrame(11));
      platform.emit(replacement.cameraId, cameraFrame(12));
      await tester.pump();
      expect(shades, [10, 12]);
      await tester.pumpWidget(const SizedBox());
      expect(stopped, 0);
      await pumpCamera(replacement);
      platform.emitError(replacement.cameraId, StateError('stream failed'));
      await tester.pump();
      await tester.pump();
      expect(stopped, 1);
      expect(platform.isStreaming(replacement.cameraId), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(stopped, 1);
      await replacement.dispose();

      platform.failNextStreamStart = PlatformException(code: 'startFailed');
      await pumpCamera(camera);
      expect(stopped, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(stopped, 2);
    });
  }
}
