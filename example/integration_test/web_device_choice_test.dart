import 'dart:js_interop';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Browser-only probe of yuv_camera's package:web implementation dependency.
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;
import 'package:yuv_camera/src/impl/yuv_camera_frame_source_web.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web source opens the device selected by each controller', (tester) async {
    await YuvFfi.initialize();
    final cameras = await availableCameras();
    final labels = cameras.map((camera) => camera.name).toList();
    binding.reportData = {'webDeviceLabels': labels};
    expect(cameras, hasLength(2), reason: 'Chrome must expose two fake video inputs');
    expect(labels.every((label) => label.isNotEmpty), isTrue, reason: 'fake device labels must be non-empty');
    expect(labels.toSet(), hasLength(2), reason: 'fake device labels must be distinct');

    final selectedIds = <String>{};
    for (final resolution in [ResolutionPreset.medium, ResolutionPreset.high]) {
      for (final camera in cameras) {
        final controller = CameraController(camera, resolution, enableAudio: false, fps: 24);
        YuvCameraFrameSourceImpl? source;
        try {
          await controller.initialize();
          final devices = (await web.window.navigator.mediaDevices.enumerateDevices().toDart).toDart;
          final expected = devices.where((device) => device.kind == 'videoinput' && device.label == camera.name).single;
          expect(expected.deviceId, isNotEmpty);
          var frameCount = 0;
          YuvCameraFrame? lastFrame;
          final errors = <Object>[];
          final activeSource = YuvCameraFrameSourceImpl(
            controller,
            onFrame: (frame) {
              frameCount++;
              lastFrame = frame;
            },
            onError: errors.add,
          );
          source = activeSource;
          await activeSource.start();
          expect(errors, isEmpty);
          final track = activeSource.videoTrackForTesting;
          if (track == null) fail('source did not attach a video track for ${camera.name}');
          final deviceId = track.getSettings().deviceId;
          expect(deviceId, expected.deviceId, reason: 'YUV source must use the controller camera ${camera.name}');
          selectedIds.add(expected.deviceId);
          for (var attempt = 0; attempt < 100 && frameCount == 0 && errors.isEmpty; attempt++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(errors, isEmpty);
          expect(frameCount, greaterThan(0), reason: 'selected device must deliver YUV frames');
          final frame = lastFrame;
          if (frame == null) fail('selected device did not deliver a frame');
          final settings = track.getSettings();
          expect((frame.width, frame.height), (settings.width, settings.height), reason: 'YUV dimensions must match the displayed stream');
          expect(frame.image.toBgraBytes().any((byte) => byte != 0), isTrue);
        } finally {
          source?.dispose();
          await controller.dispose();
        }
      }
    }
    expect(selectedIds, hasLength(2), reason: 'switching controllers must switch the source device');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
