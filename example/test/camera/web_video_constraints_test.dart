import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/web_video_constraints.dart';

void main() {
  const description = CameraDescription(name: 'Selected camera', lensDirection: CameraLensDirection.external, sensorOrientation: 0);
  const devices = [(deviceId: 'first', label: 'Other camera'), (deviceId: 'second', label: 'Selected camera')];

  test('unique non-empty label selects the exact device instead of lens direction', () {
    expect(webVideoConstraints(videoInputs: devices, description: description, resolution: ResolutionPreset.medium), {
      'deviceId': {'exact': 'second'},
      'width': {'ideal': 720},
      'height': {'ideal': 480},
    });
  });

  for (final (name, cameraName, inputs) in [
    ('empty', '', [(deviceId: 'first', label: '')]),
    ('missing', 'Missing camera', devices),
    ('duplicate', 'Selected camera', [(deviceId: 'first', label: 'Selected camera'), (deviceId: 'second', label: 'Selected camera')]),
  ]) {
    for (final direction in CameraLensDirection.values) {
      test('$name label falls back to ${direction.name} lens direction', () {
        final camera = CameraDescription(name: cameraName, lensDirection: direction, sensorOrientation: 0);
        expect(webVideoConstraints(videoInputs: inputs, description: camera, resolution: ResolutionPreset.medium), {
          'facingMode': direction == CameraLensDirection.front ? 'user' : 'environment',
          'width': {'ideal': 720},
          'height': {'ideal': 480},
        });
      });
    }
  }

  for (final (preset, width, height) in [
    (ResolutionPreset.max, 4096, 2160),
    (ResolutionPreset.ultraHigh, 4096, 2160),
    (ResolutionPreset.veryHigh, 1920, 1080),
    (ResolutionPreset.high, 1280, 720),
    (ResolutionPreset.medium, 720, 480),
    (ResolutionPreset.low, 320, 240),
  ]) {
    test('${preset.name} requests camera_web ideal dimensions', () {
      final constraints = webVideoConstraints(videoInputs: devices, description: description, resolution: preset);
      expect(constraints['width'], {'ideal': width});
      expect(constraints['height'], {'ideal': height});
    });
  }

  test('provided fps requests an ideal frame rate', () {
    final constraints = webVideoConstraints(videoInputs: devices, description: description, resolution: ResolutionPreset.medium, fps: 24);
    expect(constraints['frameRate'], {'ideal': 24});
  });

  test('absent fps leaves frame rate unconstrained', () {
    final constraints = webVideoConstraints(videoInputs: devices, description: description, resolution: ResolutionPreset.medium);
    expect(constraints, isNot(contains('frameRate')));
  });
}
