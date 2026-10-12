import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/camera_orientation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

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

  test('iOS, macOS and Linux are upright and unmirrored for every lens', () {
    for (final platform in <TargetPlatform>[TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.linux]) {
      for (final lens in CameraLensDirection.values) {
        final orientation = cameraFrameOrientation(
          platform: platform,
          lensDirection: lens,
          sensorOrientation: 270,
          deviceOrientation: DeviceOrientation.landscapeLeft,
        );
        expect(orientation, YuvFrameOrientation.upright, reason: '$platform $lens');
      }
    }
  });

  test('Windows mirrors every lens except back, without rotation', () {
    for (final lens in CameraLensDirection.values) {
      for (final sensor in <int>[0, 270]) {
        for (final device in DeviceOrientation.values) {
          final orientation = cameraFrameOrientation(
            platform: TargetPlatform.windows,
            lensDirection: lens,
            sensorOrientation: sensor,
            deviceOrientation: device,
          );
          expect(orientation.rotation.degrees, 0, reason: '$lens $sensor $device');
          expect(orientation.mirrored, lens != CameraLensDirection.back, reason: '$lens $sensor $device');
        }
      }
    }
  });

  test('browser frames mirror every lens except back, without rotation', () {
    expect(mirroredUnlessBackOrientation(CameraLensDirection.front), const YuvFrameOrientation(mirrored: true));
    expect(mirroredUnlessBackOrientation(CameraLensDirection.external), const YuvFrameOrientation(mirrored: true));
    expect(mirroredUnlessBackOrientation(CameraLensDirection.back), YuvFrameOrientation.upright);
  });
}
