import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/camera_orientation.dart';

void main() {
  test('Android orientation follows sensor/device formulas for both lenses', () {
    const deviceDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    for (final lens in <CameraLensDirection>[CameraLensDirection.back, CameraLensDirection.front]) {
      for (final sensor in <int>[90, 270]) {
        for (final entry in deviceDegrees.entries) {
          final orientation = cameraFrameOrientation(
            platform: TargetPlatform.android,
            lensDirection: lens,
            sensorOrientation: sensor,
            deviceOrientation: entry.key,
          );
          final expected = lens == CameraLensDirection.front ? (sensor + entry.value) % 360 : (sensor - entry.value + 360) % 360;
          expect(orientation.rotation.degrees, expected);
          expect(orientation.mirrored, lens == CameraLensDirection.front);
        }
      }
    }
  });

  test('iOS and desktop are upright and unmirrored', () {
    for (final platform in <TargetPlatform>[TargetPlatform.iOS, TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]) {
      final orientation = cameraFrameOrientation(
        platform: platform,
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
        deviceOrientation: DeviceOrientation.landscapeLeft,
      );
      expect(orientation.rotation.degrees, 0);
      expect(orientation.mirrored, isFalse);
    }
  });
}
