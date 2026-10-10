import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera/heavy_blur.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/ext.dart';
import 'package:yuv_camera_example/widgets/face_rect_paint.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;

  bool get _isPreviewReady => _cameraController?.value.isInitialized == true;

  Object? cameraError;
  final YuvCameraViewController viewController = YuvCameraViewController();
  FaceDetector? _faceDetector;
  Rect? _faceBox;
  bool _heavyProcessing = false;
  Duration? _lastHeavyProcessing;
  int _framesSinceFpsSample = 0;
  int _fps = 0;
  bool _shaderEnabled = false;
  DateTime _fpsSampleStarted = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    viewController.dispose();
    _faceDetector?.close().ignore();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    if (cameraError != null) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Camera error', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                            SizedBox(height: 12),
                            SelectableText(
                              '$cameraError',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    if (_cameraController case final controller? when controller.value.isInitialized) {
                      return YuvCameraView(
                        cameraController: controller,
                        viewController: viewController,
                        onFrame: _handleFrame,
                        overlayBuilder: (context, geometry) => _faceBox == null
                            ? const SizedBox.shrink()
                            : CustomPaint(
                                painter: FaceRectPainter(rect: _faceBox!, geometry: geometry, strokeWidth: 4),
                              ),
                        onFramePresented: _onFramePresented,
                      );
                    }

                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              if (_isPreviewReady)
                _CameraOverlay(
                  fps: _fps,
                  shaderEnabled: _shaderEnabled,
                  heavyProcessing: _heavyProcessing,
                  onCapture: takePicture,
                  onHeavyProcessingChanged: () => setState(() => _heavyProcessing = !_heavyProcessing),
                ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      // Closed during the lookup: dispose ran before a controller existed, so
      // one created now would never be released.
      if (!mounted) {
        return;
      }
      if (cameras.isEmpty) {
        cameraError = 'No cameras available on device';
        return;
      }

      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false, fps: 30);
      _cameraController = controller;
      await controller.initialize();
    } catch (ex) {
      cameraError = '$ex';
    } finally {
      // The screen may be closed while the camera is looked up or initialized;
      // dispose has then already released the controller.
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool get _supportsFaceDetection => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _handleFrame(YuvCameraFrame frame) async {
    if (_supportsFaceDetection) await _detectFace(frame);
    if (_heavyProcessing && (_lastHeavyProcessing == null || frame.timestamp - _lastHeavyProcessing! >= const Duration(seconds: 1))) {
      _lastHeavyProcessing = frame.timestamp;
      final image = frame.upright();
      await compute(blurBgra, (bytes: image.toBgraBytes(), width: image.width, height: image.height));
    }
  }

  void _onFramePresented(bool hasShader) {
    _framesSinceFpsSample++;
    _shaderEnabled = hasShader;
    final now = DateTime.now();
    final elapsed = now.difference(_fpsSampleStarted);
    if (elapsed < const Duration(seconds: 1)) return;
    if (mounted) setState(() => _fps = (_framesSinceFpsSample * 1000 / elapsed.inMilliseconds).round());
    _framesSinceFpsSample = 0;
    _fpsSampleStarted = now;
  }

  Future<void> _detectFace(YuvCameraFrame frame) async {
    final rotation = switch (frame.orientation.rotation) {
      YuvImageRotation.rotation0 => InputImageRotation.rotation0deg,
      YuvImageRotation.rotation90 => InputImageRotation.rotation90deg,
      YuvImageRotation.rotation180 => InputImageRotation.rotation180deg,
      YuvImageRotation.rotation270 => InputImageRotation.rotation270deg,
    };
    final detector = _faceDetector ??= FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, enableTracking: true));
    final List<Face> faces;
    try {
      faces = await detector.processImage(frame.image.toInputImage(rotation: rotation));
    } on MissingPluginException {
      return;
    }
    if (!mounted) return;
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
    setState(() => _faceBox = faces.firstOrNull?.boundingBox);
  }

  Future<void> takePicture() async {
    try {
      final yuv = _isPreviewReady ? await viewController.capture() : null;
      if (yuv == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(yuv);
    } catch (ex, stack) {
      debugPrint('takePicture error: $ex');
      debugPrint('$stack');
    }
  }
}

class _CameraOverlay extends StatelessWidget {
  const _CameraOverlay({
    required this.fps,
    required this.shaderEnabled,
    required this.heavyProcessing,
    required this.onCapture,
    required this.onHeavyProcessingChanged,
  });

  final int fps;
  final bool shaderEnabled;
  final bool heavyProcessing;
  final VoidCallback onCapture;
  final VoidCallback onHeavyProcessingChanged;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 0,
        right: 0,
        bottom: 64,
        child: Center(
          child: IconButton(
            onPressed: onCapture,
            icon: const Icon(Icons.camera, color: Colors.white, size: 64),
            tooltip: 'Capture frame',
          ),
        ),
      ),
      Positioned(
        top: 12,
        left: 56,
        child: Text('$fps fps  shader: ${shaderEnabled ? 'on' : 'off'}', style: const TextStyle(color: Colors.white)),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton(
          onPressed: onHeavyProcessingChanged,
          icon: Icon(heavyProcessing ? Icons.speed : Icons.speed_outlined, color: Colors.white),
          tooltip: 'Heavy processing once per second',
        ),
      ),
    ],
  );
}
