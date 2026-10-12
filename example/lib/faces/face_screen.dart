import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/ext.dart';
import 'package:yuv_camera_example/widgets/face_rect_paint.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Live ML Kit face box over the preview of [orchestrator]'s camera.
class FaceScreen extends StatefulWidget {
  const FaceScreen({super.key, required this.orchestrator});

  final YuvCameraOrchestrator orchestrator;

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Face detection')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: YuvCameraOrchestratorView(
                orchestrator: widget.orchestrator,
                onFrame: _supportsFaceDetection ? _detectFace : null,
                overlayBuilder: (context, geometry) => switch (_faceBox) {
                  final box? => CustomPaint(
                    painter: FaceRectPainter(rect: box, geometry: geometry, strokeWidth: 4),
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                !_supportsFaceDetection
                    ? 'Face detection needs Android or iOS'
                    : _faceBox == null
                    ? 'No face'
                    : 'Face detected',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _faceDetector?.close().ignore();
    super.dispose();
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
      // A test runner without the ML Kit plugin registered has no faces to report.
      return;
    }
    if (!mounted) return;
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
    setState(() => _faceBox = faces.firstOrNull?.boundingBox);
  }

  bool get _supportsFaceDetection => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  FaceDetector? _faceDetector;
  Rect? _faceBox;
}
