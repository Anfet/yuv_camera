import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_view.dart';
import 'package:yuv_camera/src/yuv_camera_view_controller.dart';
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

  testWidgets('capture uses the first drawn frame after camera replacement changes resolution', (tester) async {
    final viewController = YuvCameraViewController();
    await pumpView(tester, controller: viewController);
    final replacement = CameraController(
      const CameraDescription(name: 'replacement', lensDirection: CameraLensDirection.back, sensorOrientation: 0),
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await replacement.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: replacement, viewController: viewController, fit: YuvFrameFit.contain),
      ),
    );
    await settleCamera(tester);

    final capture = viewController.capture();
    var captureDone = false;
    final captured = capture.then((image) {
      captureDone = true;
      return image;
    });
    platform.emit(replacement.cameraId, cameraFrame(31, width: 10, height: 8));
    await pumpUntil(tester, () => captureDone, reason: 'capture of the replacement resolution');
    final image = await captured;
    expect(image?.size, const Size(10, 8));
    expect(image == null ? null : shadeOfYuv(image), 31);
    expect(viewController.geometry.value?.sourceSize, const Size(10, 8));

    await tester.pumpWidget(const SizedBox());
    viewController.dispose();
    await replacement.dispose();
  });

  testWidgets('capture uses changed Android orientation with unchanged raw dimensions', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final viewController = YuvCameraViewController();
    await pumpView(tester, controller: viewController);
    platform.emit(camera.cameraId, cameraFrame(21));
    await pumpUntil(tester, () => viewController.geometry.value != null, reason: 'initial geometry');

    final replacement = CameraController(
      const CameraDescription(name: 'rotated', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await replacement.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: replacement, viewController: viewController, fit: YuvFrameFit.contain),
      ),
    );
    await settleCamera(tester);
    final capture = viewController.capture();
    var captureDone = false;
    final captured = capture.then((image) {
      captureDone = true;
      return image;
    });
    platform.emit(replacement.cameraId, cameraFrame(32));
    await pumpUntil(tester, () => captureDone, reason: 'capture of the rotated frame');
    final image = await captured;

    expect(image?.size, const Size(6, 8));
    expect(viewController.geometry.value?.orientation.rotation, YuvImageRotation.rotation90);
    expect(image == null ? null : shadeOfYuv(image), 32);

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
    viewController.dispose();
    await replacement.dispose();
  });

  testWidgets('capture applies the geometry painted with the frame after viewport and fit change', (tester) async {
    final viewController = YuvCameraViewController();
    var width = 200.0;
    var height = 200.0;
    var fit = YuvFrameFit.contain;
    var alignment = Alignment.center;
    late StateSetter updateLayout;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateLayout = setState;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: YuvCameraView(cameraController: camera, viewController: viewController, fit: fit, alignment: alignment),
              ),
            );
          },
        ),
      ),
    );
    await settleCamera(tester);
    final capture = viewController.capture();
    updateLayout(() {
      width = 300;
      height = 100;
      fit = YuvFrameFit.cover;
      alignment = Alignment.topLeft;
    });
    platform.emit(camera.cameraId, cameraFrame(44));
    var captureDone = false;
    final captured = capture.then((image) {
      captureDone = true;
      return image;
    });
    await pumpUntil(tester, () => captureDone, reason: 'capture after viewport and fit change');
    final image = await captured;
    final paintedGeometry = viewController.geometry.value;
    expect(paintedGeometry?.viewSize, const Size(300, 100));
    expect(paintedGeometry?.fit, YuvFrameFit.cover);
    expect(image?.toBgraBytes(), paintedGeometry?.apply(yuvFrame(44)).toBgraBytes());

    await tester.pumpWidget(const SizedBox());
    viewController.dispose();
  });

  testWidgets('capture completes for a new frame when geometry is unchanged', (tester) async {
    final viewController = YuvCameraViewController();
    var geometryNotifications = 0;
    viewController.geometry.addListener(() => geometryNotifications++);
    await pumpView(tester, controller: viewController);
    platform.emit(camera.cameraId, cameraFrame(51));
    await pumpUntil(tester, () => viewController.geometry.value != null, reason: 'initial geometry');
    final notificationsAfterFirstFrame = geometryNotifications;

    final capture = viewController.capture();
    var captureDone = false;
    final captured = capture.then((image) {
      captureDone = true;
      return image;
    });
    platform.emit(camera.cameraId, cameraFrame(52));
    await pumpUntil(tester, () => captureDone, reason: 'capture with unchanged geometry');
    final image = await captured;
    expect(image, isNotNull);
    expect(shadeOfYuv(image!), 52);
    expect(geometryNotifications, notificationsAfterFirstFrame);

    await tester.pumpWidget(const SizedBox());
    viewController.dispose();
  });

  testWidgets('stream error between paint and deferred capture completion completes null once', (tester) async {
    platform.synchronousStreams = true;
    final viewController = YuvCameraViewController();
    var reported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(
          cameraController: camera,
          viewController: viewController,
          onFramePresented: (_) {
            if (reported) return;
            reported = true;
            platform.emitError(camera.cameraId, StateError('stopped after paint'));
          },
        ),
      ),
    );
    await settleCamera(tester);
    final capture = viewController.capture();
    platform.emit(camera.cameraId, cameraFrame(61));
    var captureDone = false;
    final captured = capture.then((image) {
      captureDone = true;
      return image;
    });
    await pumpUntil(tester, () => captureDone, reason: 'capture cancelled by an error after paint');
    expect(await captured, isNull);
    await tester.pump();
    expect(find.textContaining('Camera error:'), findsOneWidget);
    expect(await viewController.capture(), isNull);

    await tester.pumpWidget(const SizedBox());
    viewController.dispose();
  });

  testWidgets('capture requested after the stream stopped on an error completes null and a new controller captures again', (tester) async {
    final controller = YuvCameraViewController();
    Future<void> pumpCamera(CameraController cameraController) async {
      await tester.pumpWidget(
        MaterialApp(
          home: YuvCameraView(cameraController: cameraController, viewController: controller),
        ),
      );
      await settleCamera(tester);
    }

    await pumpCamera(camera);
    final beforeError = controller.capture();
    platform.emitError(camera.cameraId, StateError('stream failed'));
    await tester.pump();
    await tester.pump();
    expect(await beforeError, isNull);
    expect(find.textContaining('Camera error:'), findsOneWidget);

    expect(await controller.capture().timeout(const Duration(seconds: 1)), isNull);
    expect(await controller.capture().timeout(const Duration(seconds: 1)), isNull);

    final replacement = CameraController(camera.description, ResolutionPreset.medium, enableAudio: false);
    await replacement.initialize();
    await pumpCamera(replacement);
    expect(find.textContaining('Camera error:'), findsNothing);
    final recovered = controller.capture();
    platform.emit(replacement.cameraId, cameraFrame(20));
    await pumpUntil(tester, () => controller.geometry.value != null, reason: 'the recovered preview geometry');
    expect(await recovered, isNotNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await replacement.dispose();
  });

  testWidgets('capture after a failed stream start completes null', (tester) async {
    platform.failNextStreamStart = PlatformException(code: 'startFailed');
    final controller = YuvCameraViewController();
    await pumpView(tester, controller: controller);
    await tester.pump();
    expect(find.textContaining('Camera error:'), findsOneWidget);
    expect(await controller.capture().timeout(const Duration(seconds: 1)), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('replacement view controller gets the current geometry without a resize and without a build-phase error', (tester) async {
    final first = YuvCameraViewController();
    final replacement = YuvCameraViewController();
    var current = first;
    late StateSetter swapHandle;
    var notifications = 0;
    replacement.geometry.addListener(() => notifications++);
    var rebuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            swapHandle = setState;
            return _GeometryConsumer(
              controller: current,
              onRebuild: () => rebuilds++,
              child: YuvCameraView(cameraController: camera, viewController: current),
            );
          },
        ),
      ),
    );
    await settleCamera(tester);
    platform.emit(camera.cameraId, cameraFrame(40));
    await pumpUntil(tester, () => first.geometry.value != null, reason: 'the initial preview geometry');
    final expected = first.geometry.value;
    final rebuildsBeforeSwap = rebuilds;

    swapHandle(() => current = replacement);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(replacement.geometry.value, expected);
    expect(notifications, 1);
    expect(rebuilds, greaterThan(rebuildsBeforeSwap), reason: 'the consumer setState listener ran on the replacement geometry');
    YuvImage? image;
    var captureDone = false;
    final captured = replacement.capture().then((value) {
      image = value;
      captureDone = true;
    });
    platform.emit(camera.cameraId, cameraFrame(41));
    await pumpUntil(tester, () => captureDone, reason: 'the replacement still serves capture');
    await captured;
    expect(image, isNotNull);
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    replacement.dispose();
  });

  testWidgets('replacing the view controller together with the camera controller does not hand over stale geometry', (tester) async {
    final first = YuvCameraViewController();
    final replacement = YuvCameraViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: camera, viewController: first),
      ),
    );
    await settleCamera(tester);
    platform.emit(camera.cameraId, cameraFrame(40));
    await pumpUntil(tester, () => first.geometry.value != null, reason: 'the initial preview geometry');

    final other = CameraController(camera.description, ResolutionPreset.medium, enableAudio: false);
    await other.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraView(cameraController: other, viewController: replacement),
      ),
    );
    await tester.pump();
    expect(replacement.geometry.value, isNull);
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    replacement.dispose();
    await other.dispose();
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

/// Ancestor of the view that calls its own setState from a geometry listener; a notification fired during the view's build would throw.
class _GeometryConsumer extends StatefulWidget {
  const _GeometryConsumer({required this.controller, required this.onRebuild, required this.child});

  final YuvCameraViewController controller;
  final VoidCallback onRebuild;
  final Widget child;

  @override
  State<_GeometryConsumer> createState() => _GeometryConsumerState();
}

class _GeometryConsumerState extends State<_GeometryConsumer> {
  @override
  void initState() {
    super.initState();
    widget.controller.geometry.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _GeometryConsumer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.geometry.removeListener(_changed);
      widget.controller.geometry.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.geometry.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onRebuild();
    return widget.child;
  }
}
