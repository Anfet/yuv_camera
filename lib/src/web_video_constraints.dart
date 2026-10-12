import 'package:camera/camera.dart';

/// Matches the controller's camera label when unique, otherwise uses its lens
/// direction. Resolution and optional frame rate are browser preferences.
Map<String, Object> webVideoConstraints({
  required List<({String deviceId, String label})> videoInputs,
  required CameraDescription description,
  required ResolutionPreset resolution,
  int? fps,
}) {
  final matches = videoInputs.where((device) => device.label.isNotEmpty && device.label == description.name).toList();
  // Keep in sync with camera_web's CameraService.mapResolutionPresetToSize:
  // https://github.com/flutter/packages/blob/main/packages/camera/camera_web/lib/src/camera_service.dart
  final (width, height) = switch (resolution) {
    ResolutionPreset.max || ResolutionPreset.ultraHigh => (4096, 2160),
    ResolutionPreset.veryHigh => (1920, 1080),
    ResolutionPreset.high => (1280, 720),
    ResolutionPreset.medium => (720, 480),
    ResolutionPreset.low => (320, 240),
  };
  return {
    if (matches.length == 1)
      'deviceId': {'exact': matches.single.deviceId}
    else
      'facingMode': switch (description.lensDirection) {
        CameraLensDirection.front => 'user',
        CameraLensDirection.back || CameraLensDirection.external => 'environment',
      },
    'width': {'ideal': width},
    'height': {'ideal': height},
    if (fps != null) 'frameRate': {'ideal': fps},
  };
}
