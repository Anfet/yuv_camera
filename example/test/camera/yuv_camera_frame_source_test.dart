import 'dart:async';

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

  test('factory sources share one stream and stopping one leaves the other delivering', () async {
    final firstFrames = <YuvCameraFrame>[];
    final secondFrames = <YuvCameraFrame>[];
    final first = YuvCameraFrameSource(controller, onFrame: firstFrames.add, onError: (_) {});
    final second = YuvCameraFrameSource(controller, onFrame: secondFrames.add, onError: (_) {});

    await Future.wait([first.start(), second.start()]);
    expect(platform.listens, [controller.cameraId]);
    platform.emit(controller.cameraId, cameraFrame(12));
    await Future<void>.delayed(Duration.zero);
    expect(firstFrames, hasLength(1));
    expect(secondFrames, hasLength(1));

    first.stop();
    expect(platform.isStreaming(controller.cameraId), isTrue);
    platform.emit(controller.cameraId, cameraFrame(13));
    await Future<void>.delayed(Duration.zero);
    expect(firstFrames, hasLength(1));
    expect(secondFrames, hasLength(2));

    first.dispose();
    second.stop();
    expect(platform.isStreaming(controller.cameraId), isFalse);
    second.dispose();
    expect(platform.cancels, [controller.cameraId]);
  });

  test('restarting after the last stop waits for native stream cancellation', () async {
    final frames = <YuvCameraFrame>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: (_) {});
    await source.start();
    final stopGate = platform.stopGate = Completer<void>();
    source.stop();

    var restarted = false;
    final restarting = source.start().then((_) => restarted = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(restarted, isFalse);
    expect(platform.listens, [controller.cameraId]);

    stopGate.complete();
    await restarting;
    expect(platform.listens, [controller.cameraId, controller.cameraId]);
    expect(platform.overlappingStarts, isEmpty);
    source.dispose();
  });

  test('a new factory consumer reuses the stopped backend after the last consumer is disposed', () async {
    final first = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: (_) {});
    await first.start();
    final stopGate = platform.stopGate = Completer<void>();
    first.dispose();

    final replacement = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: (_) {});
    var restarted = false;
    final restarting = replacement.start().then((_) => restarted = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(restarted, isFalse);
    expect(platform.listens, [controller.cameraId]);

    stopGate.complete();
    await restarting;
    expect(platform.listens, [controller.cameraId, controller.cameraId]);
    expect(platform.overlappingStarts, isEmpty);
    replacement.dispose();
  });

  test('a late consumer starts its own timestamp at zero', () async {
    final firstFrames = <YuvCameraFrame>[];
    final lateFrames = <YuvCameraFrame>[];
    final first = YuvCameraFrameSource(controller, onFrame: firstFrames.add, onError: (_) {});
    final late = YuvCameraFrameSource(controller, onFrame: lateFrames.add, onError: (_) {});
    await first.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await late.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    platform.emit(controller.cameraId, cameraFrame(14));
    await Future<void>.delayed(Duration.zero);
    expect(firstFrames.single.timestamp, greaterThan(const Duration(milliseconds: 30)));
    expect(lateFrames.single.timestamp, lessThan(const Duration(milliseconds: 30)));
    first.dispose();
    late.dispose();
  });

  test('restarting one consumer resets only its timestamp without reopening the shared stream', () async {
    final frames = <YuvCameraFrame>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: (_) {});
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    platform.emit(controller.cameraId, cameraFrame(16));
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.timestamp, greaterThan(const Duration(milliseconds: 30)));

    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    platform.emit(controller.cameraId, cameraFrame(17));
    await Future<void>.delayed(Duration.zero);

    expect(frames.last.timestamp, lessThan(const Duration(milliseconds: 30)));
    expect(platform.listens, [controller.cameraId]);
    source.dispose();
  });

  test('unexpected stream EOF reports once and leaves the initialized controller alive', () async {
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: errors.add);
    await source.start();

    await platform.endStream(controller.cameraId);
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(platform.isStreaming(controller.cameraId), isFalse);
    expect(controller.value.isInitialized, isTrue);
    source.dispose();
  });

  test('one throwing callback does not prevent delivery to another consumer', () async {
    final oldHandler = FlutterError.onError;
    final reported = <FlutterErrorDetails>[];
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = oldHandler);
    var received = 0;
    final throwing = YuvCameraFrameSource(controller, onFrame: (_) => throw StateError('consumer failed'), onError: (_) {});
    final receiving = YuvCameraFrameSource(controller, onFrame: (_) => received++, onError: (_) {});
    await Future.wait([throwing.start(), receiving.start()]);

    platform.emit(controller.cameraId, cameraFrame(15));
    await Future<void>.delayed(Duration.zero);

    expect(received, 1);
    expect(reported, hasLength(1));
    throwing.dispose();
    receiving.dispose();
  });
}
