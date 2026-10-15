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

  setUpAll(YuvFfi.initialize);

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

  test('rejects a native controller whose external image stream is already active', () async {
    controller.value = controller.value.copyWith(isStreamingImages: true);
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: errors.add);

    await source.start();

    expect(errors.single, isA<StateError>().having((error) => error.message, 'message', contains('exclusive frame-stream ownership')));
    expect(platform.listens, isEmpty);
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

  test('two-plane iOS yuv420 publishes NV12 metadata and rejects malformed frames once', () async {
    final frames = <YuvCameraFrame>[];
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: errors.add);
    await source.start();
    platform.emit(controller.cameraId, _nv12Frame());
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.format, YuvPixelFormat.nv12);
    expect(frames.single.image.format, frames.single.format);
    expect(frames.single.image.uPlane.pixelStride, 2);
    expect(frames.single.image.toBgraBytes().take(4), [0, 1, 255, 255]);

    await source.start();
    platform.emit(controller.cameraId, _nv12Frame(truncateUv: true));
    platform.emit(controller.cameraId, _nv12Frame(truncateUv: true));
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(1));
    expect(errors, hasLength(1));
    expect(errors.single, isA<FormatException>());
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

  for (final disposeLastConsumer in [false, true]) {
    test('${disposeLastConsumer ? 'disposing' : 'stopping'} invalidates starts queued behind stream cancellation', () async {
      final frames = <YuvCameraFrame>[];
      final errors = <Object>[];
      final source = YuvCameraFrameSource(controller, onFrame: frames.add, onError: errors.add);
      await source.start();
      final priorListens = [...platform.listens];
      final stopGate = platform.stopGate = Completer<void>();
      source.stop();
      await Future<void>.delayed(Duration.zero);

      final openingA = source.start();
      source.stop();
      final openingB = source.start();
      if (disposeLastConsumer) {
        source.dispose();
      } else {
        source.stop();
      }

      stopGate.complete();
      await Future.wait([openingA, openingB]);
      await Future<void>.delayed(Duration.zero);
      platform.emit(controller.cameraId, cameraFrame(44));
      platform.emitError(controller.cameraId, StateError('delivery after final cancellation'));
      await Future<void>.delayed(Duration.zero);
      expect(platform.listens, priorListens, reason: 'queued starts must not reopen after the final stop');
      expect(platform.isStreaming(controller.cameraId), isFalse);
      expect(platform.overlappingStarts, isEmpty);
      expect(frames, isEmpty, reason: 'no frame may be delivered after the final stop or dispose');
      expect(errors, isEmpty, reason: 'no stream error may be delivered after the final stop or dispose');
      if (!disposeLastConsumer) source.dispose();
    });
  }

  test('a frame fan-out skips a consumer restarted by an earlier callback', () async {
    final firstFrames = <int>[];
    final secondFrames = <int>[];
    late YuvCameraFrameSource second;
    var restartSecond = true;
    final first = YuvCameraFrameSource(
      controller,
      onFrame: (frame) {
        firstFrames.add(frame.image.toBgraBytes()[0]);
        if (restartSecond) {
          restartSecond = false;
          second.start();
        }
      },
      onError: (_) {},
    );
    second = YuvCameraFrameSource(controller, onFrame: (frame) => secondFrames.add(frame.image.toBgraBytes()[0]), onError: (_) {});
    await Future.wait([first.start(), second.start()]);

    platform.emit(controller.cameraId, cameraFrame(31));
    await Future<void>.delayed(Duration.zero);
    expect(firstFrames, [31]);
    expect(secondFrames, isEmpty, reason: 'the restarted delivery must not receive its predecessor frame');

    platform.emit(controller.cameraId, cameraFrame(32));
    await Future<void>.delayed(Duration.zero);
    expect(secondFrames, [32]);
    first.dispose();
    second.dispose();
  });

  test('terminal fan-out skips stale recipients restarted or created by an error callback', () async {
    final firstErrors = <Object>[];
    final secondErrors = <Object>[];
    final newErrors = <Object>[];
    final secondFrames = <int>[];
    late YuvCameraFrameSource second;
    late YuvCameraFrameSource added;
    var recoveryStarted = false;
    final first = YuvCameraFrameSource(
      controller,
      onFrame: (_) {},
      onError: (error) {
        firstErrors.add(error);
        if (recoveryStarted) return;
        recoveryStarted = true;
        second.start();
        added.start();
      },
    );
    second = YuvCameraFrameSource(controller, onFrame: (frame) => secondFrames.add(frame.image.toBgraBytes()[0]), onError: secondErrors.add);
    added = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: newErrors.add);
    await Future.wait([first.start(), second.start()]);

    platform.emitError(controller.cameraId, StateError('terminal'));
    await Future<void>.delayed(Duration.zero);
    expect(firstErrors, hasLength(1));
    expect(secondErrors, isEmpty, reason: 'the restarted consumer must not receive the old terminal error');
    expect(newErrors, isEmpty, reason: 'a newly created delivery was absent from the terminal snapshot');
    expect(platform.listens, [controller.cameraId, controller.cameraId]);

    platform.emit(controller.cameraId, cameraFrame(33));
    await Future<void>.delayed(Duration.zero);
    expect(secondFrames, [33]);
    expect(secondErrors, isEmpty);
    first.dispose();
    second.dispose();
    added.dispose();
  });

  test('terminal errors skip disposed consumers and intentional stops remain quiet', () async {
    final firstErrors = <Object>[];
    final secondErrors = <Object>[];
    final first = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: firstErrors.add);
    final second = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: secondErrors.add);
    await Future.wait([first.start(), second.start()]);
    first.stop();
    second.dispose();
    expect(firstErrors, isEmpty);
    expect(secondErrors, isEmpty);

    await first.start();
    await first.start();
    platform.emitError(controller.cameraId, StateError('terminal once'));
    await Future<void>.delayed(Duration.zero);
    expect(firstErrors, hasLength(1));
    expect(secondErrors, isEmpty);
    first.dispose();
  });

  test('terminal errors reach both active consumers exactly once', () async {
    final firstErrors = <Object>[];
    final secondErrors = <Object>[];
    final first = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: firstErrors.add);
    final second = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: secondErrors.add);
    await Future.wait([first.start(), second.start()]);

    platform.emitError(controller.cameraId, StateError('terminal for all active consumers'));
    await Future<void>.delayed(Duration.zero);
    expect(firstErrors, hasLength(1));
    expect(secondErrors, hasLength(1));
    first.dispose();
    second.dispose();
  });

  test('controller-value errors stop the stream, ignore late frames, and detach the listener when idle', () async {
    final frames = <int>[];
    final errors = <Object>[];
    final source = YuvCameraFrameSource(controller, onFrame: (frame) => frames.add(frame.image.toBgraBytes()[0]), onError: errors.add);
    await source.start();
    final stopGate = platform.stopGate = Completer<void>();

    controller.value = controller.value.copyWith(errorDescription: 'controller-value failure');
    expect(errors, hasLength(1));
    expect(platform.cancels, [controller.cameraId]);

    platform.emit(controller.cameraId, cameraFrame(41));
    controller.value = controller.value.copyWith(errorDescription: 'recovered');
    await Future<void>.delayed(Duration.zero);
    expect(frames, isEmpty);
    expect(errors, hasLength(1));
    expect(platform.isStreaming(controller.cameraId), isFalse);

    stopGate.complete();
    await source.start();
    platform.emit(controller.cameraId, cameraFrame(42));
    await Future<void>.delayed(Duration.zero);
    expect(frames, [42]);
    source.stop();

    controller.value = controller.value.copyWith(errorDescription: 'inactive controller error');
    expect(errors, hasLength(1), reason: 'the controller listener is detached when there is no active consumer');
    controller.value = controller.value.copyWith(errorDescription: 'recovered');
    source.dispose();
  });

  test('terminal error skips a recipient disposed by an earlier error callback', () async {
    final firstErrors = <Object>[];
    final secondErrors = <Object>[];
    late YuvCameraFrameSource second;
    final first = YuvCameraFrameSource(
      controller,
      onFrame: (_) {},
      onError: (error) {
        firstErrors.add(error);
        second.dispose();
      },
    );
    second = YuvCameraFrameSource(controller, onFrame: (_) {}, onError: secondErrors.add);
    await Future.wait([first.start(), second.start()]);

    platform.emitError(controller.cameraId, StateError('terminal before dispose callback'));
    await Future<void>.delayed(Duration.zero);
    expect(firstErrors, hasLength(1));
    expect(secondErrors, isEmpty, reason: 'a disposed recipient must not receive a snapshotted terminal error');
    first.dispose();
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

CameraImageData _nv12Frame({bool truncateUv = false}) {
  final uv = Uint8List.fromList([90, 240, 54, 34, 0xee, 90, 240, 54, 34]);
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 875704438),
    width: 3,
    height: 3,
    planes: [
      CameraImagePlane(
        bytes: Uint8List.fromList([82, 82, 82, 0xee, 82, 82, 82, 0xee, 82, 82, 82]),
        bytesPerRow: 4,
        bytesPerPixel: null,
        width: 3,
        height: 3,
      ),
      CameraImagePlane(bytes: truncateUv ? Uint8List.fromList(uv.take(7).toList()) : uv, bytesPerRow: 5, bytesPerPixel: null, width: 2, height: 2),
    ],
  );
}
