import 'dart:convert';

import 'package:flutter/foundation.dart';

const Duration deviceCheckMeasurementDuration = Duration(seconds: 5);

/// Collects one release-device validation result in the documented schema.
final class DeviceCheckReport {
  DeviceCheckReport({
    required this.gitSha,
    required this.operatingSystem,
    required this.cameraLens,
    required this.sensorOrientation,
    required this.steps,
    required this.notes,
  });

  final String gitSha;
  final String operatingSystem;
  final String cameraLens;
  final int sensorOrientation;
  final List<DeviceCheckStepResult> steps;
  final String notes;

  String get json => const JsonEncoder.withIndent('  ').convert(toJson());

  Map<String, Object?> toJson() => {
    'card': 'DEVICE-1',
    'schema': 1,
    'build_mode': _buildMode,
    'git_sha': gitSha,
    'os': operatingSystem,
    'camera': {'lens': cameraLens, 'sensor_orientation': sensorOrientation, 'preset': 'medium'},
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    'notes': notes,
  };
}

/// Values recorded for one ordered device-check step.
final class DeviceCheckStepResult {
  const DeviceCheckStepResult({
    required this.id,
    required this.skipped,
    required this.seconds,
    this.displayFps,
    this.shader,
    this.rotation,
    this.mirrored,
    this.frame,
    this.blurRuns,
    this.blurMsMedian,
    this.faceRatio,
    this.answer,
    this.capture,
  });

  final String id;
  final bool skipped;
  final double seconds;
  final double? displayFps;

  /// Shader availability when a frame was presented; JSON schema 1 retains this field.
  /// A true value does not prove shader paint: BGRA or unsupported layouts can use fallback.
  final bool? shader;
  final int? rotation;
  final bool? mirrored;
  final String? frame;
  final int? blurRuns;
  final double? blurMsMedian;
  final double? faceRatio;
  final bool? answer;
  final String? capture;

  Map<String, Object?> toJson() => {
    'id': id,
    'skipped': skipped,
    'seconds': _round(seconds),
    if (displayFps case final value?) 'display_fps': _round(value),
    if (shader case final value?) 'shader': value,
    if (rotation case final value?) 'rotation': value,
    if (mirrored case final value?) 'mirrored': value,
    if (frame case final value?) 'frame': value,
    if (blurRuns case final value?) 'blur_runs': value,
    if (blurMsMedian case final value?) 'blur_ms_median': _round(value),
    if (faceRatio case final value?) 'face_ratio': _round(value),
    if (answer case final value?) 'answer': value,
    if (capture case final value?) 'capture': value,
  };
}

/// Counts shown frames for exactly one step measurement window.
final class DeviceCheckMeasurement {
  final Stopwatch _stopwatch = Stopwatch();
  int _presented = 0;
  bool? _shader;
  int? _rotation;
  bool? _mirrored;
  String? _frame;

  void start() {
    _presented = 0;
    _shader = null;
    _rotation = null;
    _mirrored = null;
    _frame = null;
    _stopwatch
      ..reset()
      ..start();
  }

  void presented({required bool shader, required int rotation, required bool mirrored, required int width, required int height}) {
    if (!_stopwatch.isRunning) return;
    _presented++;
    _shader = shader;
    _rotation = rotation;
    _mirrored = mirrored;
    _frame = '${width}x$height';
  }

  DeviceCheckStepResult finish({required String id, int? blurRuns, List<Duration> blurDurations = const [], double? faceRatio, String? capture}) {
    _stopwatch.stop();
    final seconds = _stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    return DeviceCheckStepResult(
      id: id,
      skipped: false,
      seconds: seconds,
      displayFps: seconds == 0 ? 0 : _presented / seconds,
      shader: _shader,
      rotation: _rotation,
      mirrored: _mirrored,
      frame: _frame,
      blurRuns: blurRuns,
      blurMsMedian: blurDurations.isEmpty ? null : _medianMilliseconds(blurDurations),
      faceRatio: faceRatio,
      capture: capture,
    );
  }
}

double _medianMilliseconds(List<Duration> values) {
  final milliseconds = values.map((value) => value.inMicroseconds / Duration.microsecondsPerMillisecond).toList()..sort();
  final middle = milliseconds.length ~/ 2;
  return milliseconds.length.isOdd ? milliseconds[middle] : (milliseconds[middle - 1] + milliseconds[middle]) / 2;
}

double _round(double value) => (value * 10).roundToDouble() / 10;

String get _buildMode => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';
// ignore_for_file: use_null_aware_elements
