import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;
  late CameraController controller;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    controller = CameraController((await availableCameras()).first, ResolutionPreset.medium, enableAudio: false);
    await controller.initialize();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await controller.dispose();
  });

  test('delivers frames until stop and reports current stream errors', () async {
    final frames = <YuvCameraFrame>[];
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: errors.add);
    await source.start();
    platform.emit(controller.cameraId, cameraFrame(12));
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(1));
    expect(frames.single.image.width, frameWidth);
    source.stop();
    platform.emit(controller.cameraId, cameraFrame(13));
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(1));

    await source.start();
    platform.emitError(controller.cameraId, StateError('camera failed'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    source.dispose();
  });

  test('an unsupported image format group stops the source with one error', () async {
    final frames = <YuvCameraFrame>[];
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: errors.add);
    await source.start();
    platform.emit(controller.cameraId, nv21Frame());
    platform.emit(controller.cameraId, nv21Frame());
    await Future<void>.delayed(Duration.zero);
    expect(frames, isEmpty);
    expect(errors.single, isUnsupportedError);
    expect(platform.isStreaming(controller.cameraId), isFalse);
    source.dispose();
  });

  test('Windows front-camera frames are mirrored and not rotated', () async {
    final frames = <YuvCameraFrame>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: (_) {});
    await source.start();
    platform.emit(controller.cameraId, cameraFrame(12));
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.orientation, const YuvFrameOrientation(mirrored: true));
    source.dispose();
  });
}
