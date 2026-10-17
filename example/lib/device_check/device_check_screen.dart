import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera/heavy_blur.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/device_check/device_check_report.dart';
import 'package:yuv_camera_example/ext.dart';
import 'package:yuv_camera_example/widgets/face_rect_paint.dart';

/// Guided on-device validation for the release checklist.
class DeviceCheckScreen extends StatefulWidget {
  const DeviceCheckScreen({super.key, this.orchestrator, this.cameraEnabled = true}) : assert(!cameraEnabled || orchestrator != null);

  /// Owner of the camera the check leases; required unless [cameraEnabled] is `false`.
  final YuvCameraOrchestrator? orchestrator;

  final bool cameraEnabled;

  @override
  State<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  static const String _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'unknown');
  static const List<_DeviceCheckStep> _steps = [
    _DeviceCheckStep(
      'portrait_idle',
      'Keep the camera in its normal position and facing you. Tap Start and hold still.',
      measures: true,
      fixedCameraId: 'preview_idle',
    ),
    _DeviceCheckStep(
      'portrait_heavy',
      'Keep the camera in its normal position. Tap Start and hold still while a heavy blur runs in the background.',
      measures: true,
      heavy: true,
      fixedCameraId: 'preview_heavy',
    ),
    _DeviceCheckStep(
      'landscape',
      'Turn the phone sideways (either direction) and keep your face in the preview. Tap Start and hold still.',
      measures: true,
      question: 'Is the preview upright, with your head at the top of the screen?',
      requiresDeviceRotation: true,
    ),
    _DeviceCheckStep(
      'face_portrait',
      'Turn the phone upright and keep your face in the preview. Tap Start, hold still and watch for a box around your face.',
      measures: true,
      face: true,
      question: 'Did the box stay on your face?',
    ),
    _DeviceCheckStep(
      'face_landscape',
      'Turn the phone sideways and keep your face in the preview. Tap Start, hold still and watch for a box around your face.',
      measures: true,
      face: true,
      question: 'Did the box stay on your face?',
      requiresDeviceRotation: true,
    ),
    _DeviceCheckStep(
      'mirror',
      'Keep the camera facing you and raise your right hand next to your face. Then tap Next.',
      question: 'Is your raised hand on the right side of the screen, as in a mirror?',
    ),
    _DeviceCheckStep(
      'capture',
      'Keep the camera facing you and tap Capture. The captured frame appears in the bottom-right corner.',
      question: 'Does the captured frame in the corner match the preview: same rotation, same mirror side, same framing?',
      capture: true,
    ),
  ];

  final YuvCameraViewController _viewController = YuvCameraViewController();
  final DeviceCheckMeasurement _measurement = DeviceCheckMeasurement();
  final List<DeviceCheckStepResult> _results = [];
  final List<Duration> _blurDurations = [];
  final TextEditingController _notesController = TextEditingController();
  YuvCameraLease? _lease;
  FaceDetector? _faceDetector;
  CameraDescription? _camera;
  Rect? _faceBox;
  YuvFramePresenter? _capturePresenter;
  YuvImage? _captureImage;
  int _stepIndex = 0;
  int _blurRuns = 0;
  // Identifies the current measurement so a late result of an earlier step cannot enter a later one.
  int _measurementId = 0;
  int _faceFrames = 0;
  int _faceFramesWithFace = 0;
  bool _measuring = false;
  bool _awaitingAnswer = false;
  bool _cameraReady = false;
  bool _readyLogged = false;
  Duration? _lastBlur;
  Object? _cameraError;
  DeviceCheckStepResult? _pendingResult;

  late final List<_DeviceCheckStep> _availableSteps = _steps
      .where((step) => (!step.requiresDeviceRotation || _supportsDeviceRotation) && (!step.face || _supportsFaceDetection))
      .toList(growable: false);

  _DeviceCheckStep get _step => _availableSteps[_stepIndex];

  String get _stepId => _supportsDeviceRotation ? _step.id : _step.fixedCameraId ?? _step.id;

  @override
  void initState() {
    super.initState();
    if (widget.cameraEnabled) _initializeCamera();
  }

  @override
  void dispose() {
    _viewController.dispose();
    _faceDetector?.close().ignore();
    _lease?.release();
    _capturePresenter?.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_results.length == _availableSteps.length) return _buildResult(context);
    final compact = MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kReleaseMode)
              const ColoredBox(
                color: Colors.amber,
                child: Padding(padding: EdgeInsets.all(8), child: Text('Run this check in release mode.')),
              ),
            Expanded(child: _buildPreview()),
            Padding(
              padding: EdgeInsets.all(compact ? 8 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: compact ? 6 : 12,
                children: [
                  Text('Step ${_stepIndex + 1}/${_availableSteps.length}: $_stepId', style: Theme.of(context).textTheme.titleSmall),
                  if (!_supportsDeviceRotation) const Text('Phone-rotation and face-detection checks are omitted on this platform.'),
                  if (_awaitingAnswer && _step.question != null)
                    Text(_step.question!, style: Theme.of(context).textTheme.titleMedium)
                  else
                    Text(_step.instruction),
                  if (_measuring) Text('Measuring for ${deviceCheckMeasurementDuration.inSeconds} seconds. Hold still.'),
                  if (_measuring) const LinearProgressIndicator(),
                  if (_awaitingAnswer) _answerControls() else _actionControls(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (!widget.cameraEnabled) return const ColoredBox(color: Colors.black);
    if (_cameraError case final error?) return Center(child: Text('Camera error: $error'));
    final lease = _lease;
    if (!_cameraReady || lease == null) return const Center(child: CircularProgressIndicator());
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvCameraView(
          cameraController: lease.controller,
          viewController: _viewController,
          onFrame: _handleFrame,
          onFramePresented: _onFramePresented,
          overlayBuilder: (context, geometry) => _faceBox == null
              ? const SizedBox.shrink()
              : CustomPaint(
                  painter: FaceRectPainter(rect: _faceBox!, geometry: geometry),
                ),
        ),
        if (_capturePresenter case final presenter?)
          Positioned(
            right: 12,
            bottom: 12,
            width: 160,
            child: AspectRatio(
              aspectRatio: _captureImage!.width / _captureImage!.height,
              child: YuvFrameView(presenter: presenter, fit: YuvFrameFit.contain),
            ),
          ),
      ],
    );
  }

  Widget _actionControls() {
    if (_step.capture) {
      return Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 12,
        children: [
          Expanded(
            child: FilledButton(onPressed: _cameraReady || !widget.cameraEnabled ? _capture : null, child: const Text('Capture')),
          ),
          OutlinedButton(onPressed: _skip, child: const Text('Skip')),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 12,
      children: [
        Expanded(
          child: FilledButton(onPressed: _measuring ? null : _start, child: Text(_step.measures ? 'Start' : 'Next')),
        ),
        OutlinedButton(onPressed: _measuring ? null : _skip, child: const Text('Skip')),
      ],
    );
  }

  Widget _answerControls() => Row(
    mainAxisSize: MainAxisSize.max,
    crossAxisAlignment: CrossAxisAlignment.center,
    spacing: 12,
    children: [
      Expanded(
        child: FilledButton(onPressed: () => _answer(true), child: const Text('Yes')),
      ),
      Expanded(
        child: OutlinedButton(onPressed: () => _answer(false), child: const Text('No')),
      ),
    ],
  );

  Widget _buildResult(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Device check result')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(report.json, style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
                onChanged: (_) => setState(() {}),
              ),
              FilledButton.icon(onPressed: _shareReport, icon: const Icon(Icons.share), label: const Text('Share')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareReport() async {
    await SharePlus.instance.share(ShareParams(text: _report.json, title: 'Device check result'));
  }

  Future<void> _initializeCamera() async {
    try {
      final orchestrator = widget.orchestrator;
      if (orchestrator == null) throw StateError('The device check needs a camera orchestrator.');
      final lease = await orchestrator.acquire();
      // A lease that arrives after the last step has no preview to serve; the result screen is already shown.
      if (!mounted || _results.length == _availableSteps.length) {
        lease.release();
        return;
      }
      setState(() {
        _camera = lease.controller.description;
        _lease = lease;
        _cameraReady = true;
      });
    } catch (error) {
      if (mounted) setState(() => _cameraError = error);
    }
  }

  void _start() {
    if (!_step.measures) {
      _awaitAnswerOrAdvance(_emptyResult());
      return;
    }
    _blurRuns = 0;
    _blurDurations.clear();
    _faceFrames = 0;
    _faceFramesWithFace = 0;
    _measurement.start();
    final measurementId = ++_measurementId;
    setState(() => _measuring = true);
    Future<void>.delayed(deviceCheckMeasurementDuration, () {
      if (!mounted || !_measuring || measurementId != _measurementId) return;
      final result = _measurement.finish(
        id: _stepId,
        blurRuns: _step.heavy ? _blurRuns : null,
        blurDurations: _blurDurations,
        faceRatio: _step.face && _faceFrames > 0 ? _faceFramesWithFace / _faceFrames : null,
      );
      _log('Device check step ${jsonEncode(result.toJson())}');
      setState(() {
        _measuring = false;
        _faceBox = null;
      });
      _awaitAnswerOrAdvance(result);
    });
  }

  Future<void> _capture() async {
    final image = await _viewController.capture();
    if (!mounted) return;
    if (image != null) {
      setState(() {
        _capturePresenter?.dispose();
        _capturePresenter = YuvFramePresenter(useShader: true)..present(image);
        _captureImage = image;
      });
    }
    _awaitAnswerOrAdvance(_emptyResult(capture: image == null ? null : '${image.width}x${image.height}'));
  }

  void _skip() {
    final result = DeviceCheckStepResult(id: _stepId, skipped: true, seconds: 0);
    _log('Device check step ${jsonEncode(result.toJson())}');
    _advance(result);
  }

  void _answer(bool value) {
    final current = _pendingResult;
    if (current == null) return;
    _pendingResult = null;
    _advance(
      DeviceCheckStepResult(
        id: current.id,
        skipped: current.skipped,
        seconds: current.seconds,
        displayFps: current.displayFps,
        shader: current.shader,
        rotation: current.rotation,
        mirrored: current.mirrored,
        frame: current.frame,
        blurRuns: current.blurRuns,
        blurMsMedian: current.blurMsMedian,
        faceRatio: current.faceRatio,
        answer: value,
        capture: current.capture,
      ),
    );
  }

  void _awaitAnswerOrAdvance(DeviceCheckStepResult result) {
    if (_step.question == null) {
      _advance(result);
      return;
    }
    setState(() {
      _pendingResult = result;
      _awaitingAnswer = true;
    });
  }

  void _advance(DeviceCheckStepResult result) {
    final lease = _lease;
    setState(() {
      _awaitingAnswer = false;
      _results.add(result);
      if (_results.length < _availableSteps.length) {
        _stepIndex++;
      } else {
        // The result screen replaces the preview in this frame; the camera goes back once the preview is unmounted.
        _lease = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => lease?.release());
      }
    });
    if (_results.length == _availableSteps.length) _log('Device check result ${_report.json}');
  }

  DeviceCheckStepResult _emptyResult({String? capture}) => DeviceCheckStepResult(id: _stepId, skipped: false, seconds: 0, capture: capture);

  // The JSON shader field records shader availability, not the paint path of this frame.
  void _onFramePresented(bool shader) {
    final camera = _camera;
    final geometry = _viewController.geometry.value;
    if (camera == null || geometry == null) return;
    _measurement.presented(
      shader: shader,
      rotation: _rotationDegrees(geometry.orientation.rotation),
      mirrored: geometry.orientation.mirrored,
      width: geometry.sourceSize.width.round(),
      height: geometry.sourceSize.height.round(),
    );
    if (!_readyLogged) {
      _readyLogged = true;
      debugPrint(
        'Device ready {"build_mode":"${kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug'}","shader":$shader}',
      );
    }
  }

  Future<void> _handleFrame(YuvCameraFrame frame) async {
    final measurementId = _measurementId;
    if (_step.heavy && _measuring && (_lastBlur == null || frame.timestamp - _lastBlur! >= const Duration(seconds: 1))) {
      _lastBlur = frame.timestamp;
      final image = frame.upright();
      final stopwatch = Stopwatch()..start();
      await compute(blurBgra, (bytes: image.toBgraBytes(), width: image.width, height: image.height));
      stopwatch.stop();
      if (!mounted || !_measuring || measurementId != _measurementId) return;
      _blurRuns++;
      _blurDurations.add(stopwatch.elapsed);
    }
    if (_step.face && _measuring && _supportsFaceDetection) await _detectFace(frame, measurementId);
  }

  bool get _supportsDeviceRotation => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  bool get _supportsFaceDetection => _supportsDeviceRotation;

  Future<void> _detectFace(YuvCameraFrame frame, int measurementId) async {
    final rotation = switch (frame.orientation.rotation) {
      YuvImageRotation.rotation0 => InputImageRotation.rotation0deg,
      YuvImageRotation.rotation90 => InputImageRotation.rotation90deg,
      YuvImageRotation.rotation180 => InputImageRotation.rotation180deg,
      YuvImageRotation.rotation270 => InputImageRotation.rotation270deg,
    };
    final detector = _faceDetector ??= FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, enableTracking: true));
    try {
      final faces = await detector.processImage(frame.image.toInputImage(rotation: rotation));
      // A detection finishing after its measurement ended must neither bring the box back nor count in a later step.
      if (!mounted || !_measuring || measurementId != _measurementId) return;
      _faceFrames++;
      if (faces.isNotEmpty) _faceFramesWithFace++;
      faces.sort(
        (first, second) => (second.boundingBox.width * second.boundingBox.height).compareTo(first.boundingBox.width * first.boundingBox.height),
      );
      setState(() => _faceBox = faces.firstOrNull?.boundingBox);
    } on MissingPluginException {
      // Desktop test runners have no ML Kit registration; this check runs only on Android or iOS.
    }
  }

  DeviceCheckReport get _report {
    final camera = _camera;
    return DeviceCheckReport(
      gitSha: _gitSha,
      operatingSystem: defaultTargetPlatform.name,
      cameraLens: camera?.lensDirection.name ?? 'front',
      sensorOrientation: camera?.sensorOrientation ?? 0,
      steps: _results,
      notes: _notesController.text,
    );
  }

  void _log(String message) {
    if (widget.cameraEnabled) debugPrint(message);
  }
}

final class _DeviceCheckStep {
  const _DeviceCheckStep(
    this.id,
    this.instruction, {
    this.measures = false,
    this.heavy = false,
    this.face = false,
    this.question,
    this.capture = false,
    this.requiresDeviceRotation = false,
    this.fixedCameraId,
  });

  final String id;
  final String instruction;
  final bool measures;
  final bool heavy;
  final bool face;
  final String? question;
  final bool capture;
  final bool requiresDeviceRotation;
  final String? fixedCameraId;
}

int _rotationDegrees(YuvImageRotation rotation) => switch (rotation) {
  YuvImageRotation.rotation0 => 0,
  YuvImageRotation.rotation90 => 90,
  YuvImageRotation.rotation180 => 180,
  YuvImageRotation.rotation270 => 270,
};
