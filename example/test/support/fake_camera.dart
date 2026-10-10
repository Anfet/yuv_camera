import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const int frameWidth = 8;
const int frameHeight = 6;

/// A grey BGRA frame the way camera_desktop delivers it: one plane, every
/// channel equal to [shade], so the decoded pixels tell which frame is shown.
/// [rowPadding] extra bytes per row model a native stride above `width * 4`.
CameraImageData cameraFrame(int shade, {int rowPadding = 0}) {
  final bytesPerRow = frameWidth * 4 + rowPadding;
  final bytes = Uint8List(bytesPerRow * frameHeight);
  for (int row = 0; row < frameHeight; row++) {
    for (int col = 0; col < frameWidth; col++) {
      final offset = row * bytesPerRow + col * 4;
      bytes.setRange(offset, offset + 4, [shade, shade, shade, 255]);
    }
  }
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
    width: frameWidth,
    height: frameHeight,
    planes: [CameraImagePlane(bytes: bytes, bytesPerRow: bytesPerRow, bytesPerPixel: 4, width: frameWidth, height: frameHeight)],
  );
}

YuvImage yuvFrame(int shade) {
  final frame = YuvImage.bgra(frameWidth, frameHeight);
  frame.yPlane.assignFrom(
    Uint8List.fromList([
      for (int i = 0; i < frameWidth * frameHeight; i++) ...[shade, shade, shade, 255],
    ]),
  );
  frame.markDirty();
  return frame;
}

int shadeOfYuv(YuvImage image) => image.toBgraBytes()[0];

/// Stands in for the camera plugin: one single-subscription frame stream per
/// `onStreamedFrameAvailable` call, whose cancel is the native stop. Serves
/// the direct subscriptions of the mobile and desktop previews; [emitError]
/// is a camera error after the stream started.
///
/// Like camera_desktop and the mobile plugins it keeps one active stream per
/// camera; a second listen on a camera whose previous stream is still
/// stopping is recorded in [overlappingStarts].
class FakeCameraPlatform extends CameraPlatform {
  final _events = StreamController<CameraEvent>.broadcast();
  final Map<int, StreamController<CameraImageData>> _activeStreams = {};
  final Set<int> _stopping = {};
  int _nextCameraId = 1;

  final List<int> disposedCameras = [];
  final List<int> listens = [];
  final List<int> cancels = [];
  final List<int> overlappingStarts = [];

  /// When set, the native stop of a cancelled stream waits for it.
  Completer<void>? stopGate;

  /// When set, `initializeCamera` waits for it.
  Completer<void>? initializeGate;

  /// When set, `availableCameras` waits for it.
  Completer<void>? lookupGate;

  /// When set, the next `onStreamedFrameAvailable` call throws it, the way a
  /// plugin reports a camera that cannot stream.
  PlatformException? failNextStreamStart;

  int createdCameras = 0;

  bool isStreaming(int cameraId) => _activeStreams.containsKey(cameraId);

  /// Delivers [frame] to the stream currently listened to on [cameraId], if any.
  void emit(int cameraId, CameraImageData frame) => _activeStreams[cameraId]?.add(frame);

  void emitError(int cameraId, Object error) => _activeStreams[cameraId]?.addError(error);

  @override
  Future<List<CameraDescription>> availableCameras() async {
    await lookupGate?.future;
    return const [CameraDescription(name: 'fake-camera', lensDirection: CameraLensDirection.front, sensorOrientation: 0)];
  }

  @override
  Future<int> createCameraWithSettings(CameraDescription cameraDescription, MediaSettings? mediaSettings) async {
    createdCameras++;
    return _nextCameraId++;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    await initializeGate?.future;
    _events.add(CameraInitializedEvent(cameraId, frameWidth.toDouble(), frameHeight.toDouble(), ExposureMode.auto, false, FocusMode.auto, false));
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _events.stream.where((event) => event.cameraId == cameraId).cast<CameraInitializedEvent>();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _events.stream.where((event) => event.cameraId == cameraId && event is CameraErrorEvent).cast<CameraErrorEvent>();

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId, {CameraImageStreamOptions? options}) {
    final failure = failNextStreamStart;
    if (failure != null) {
      failNextStreamStart = null;
      throw failure;
    }

    late final StreamController<CameraImageData> controller;
    controller = StreamController<CameraImageData>(
      onListen: () {
        listens.add(cameraId);
        if (_activeStreams.containsKey(cameraId) || _stopping.contains(cameraId)) {
          overlappingStarts.add(cameraId);
        }
        _activeStreams[cameraId] = controller;
      },
      onCancel: () async {
        cancels.add(cameraId);
        if (identical(_activeStreams[cameraId], controller)) {
          _activeStreams.remove(cameraId);
        }
        _stopping.add(cameraId);
        await stopGate?.future;
        _stopping.remove(cameraId);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameras.add(cameraId);
    await _activeStreams.remove(cameraId)?.close();
  }
}

ui.Image? drawnImage(WidgetTester tester) {
  final raw = find.byType(RawImage);
  return raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
}

Future<int?> drawnShade(WidgetTester tester) async {
  final image = drawnImage(tester);
  if (image == null) {
    return null;
  }
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  return data!.getUint8(0);
}

/// Decode callbacks only arrive outside the test's fake clock: each round
/// gives the engine real time, then runs the fake microtasks and draws a frame
/// if a decoded one is waiting.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String reason = 'condition'}) async {
  for (int i = 0; i < 400 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $reason');
}

/// Gives a decode that may still be running enough real time to finish, then
/// draws whatever it produced.
Future<void> settleDecodes(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(Duration.zero);
  await tester.pump();
}
