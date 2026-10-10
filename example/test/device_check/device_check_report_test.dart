import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera_example/device_check/device_check_report.dart';

void main() {
  test('records FPS, median, rounded values, and the DEVICE-1 schema', () {
    final measurement = DeviceCheckMeasurement()..start();
    measurement.presented(shader: true, rotation: 270, mirrored: true, width: 720, height: 480);
    final step = measurement.finish(
      id: 'portrait_heavy',
      blurRuns: 14,
      blurDurations: const [Duration(milliseconds: 100), Duration(milliseconds: 300)],
    );
    final report = DeviceCheckReport(
      gitSha: 'abc1234',
      operatingSystem: 'android',
      cameraLens: 'front',
      sensorOrientation: 270,
      steps: [
        step,
        const DeviceCheckStepResult(id: 'mirror', skipped: true, seconds: 0),
      ],
      notes: 'stable',
    );

    final json = jsonDecode(report.json) as Map<String, Object?>;
    expect(json['card'], 'DEVICE-1');
    expect(json['schema'], 1);
    expect(json['build_mode'], isA<String>());
    expect(json['git_sha'], 'abc1234');
    expect(json['camera'], {'lens': 'front', 'sensor_orientation': 270, 'preset': 'medium'});
    final steps = json['steps'] as List<Object?>;
    expect((steps.first! as Map<String, Object?>)['blur_ms_median'], 200.0);
    expect((steps.last! as Map<String, Object?>)['skipped'], isTrue);
  });
}
