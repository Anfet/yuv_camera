import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/ext.dart';

class CaptureResultScreen extends StatefulWidget {
  const CaptureResultScreen({super.key, required this.image});

  final YuvImage image;

  @override
  State<CaptureResultScreen> createState() => CaptureResultScreenState();
}

class CaptureResultScreenState extends State<CaptureResultScreen> {
  late final YuvFramePresenter _presenter = YuvFramePresenter(useShader: true)..present(widget.image);
  FaceDetector? _detector;
  String _result = 'Captured frame';
  Rect? faceBox;

  bool get _supportsFaceDetection => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  YuvImage get image => widget.image;

  @override
  void dispose() {
    _presenter.dispose();
    _detector?.close();
    super.dispose();
  }

  Future<void> detectFace() async {
    final detector = _detector ??= FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
    final faces = await detector.processImage(image.toInputImage());
    if (mounted) {
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      setState(() {
        faceBox = faces.firstOrNull?.boundingBox;
        _result = faceBox == null ? 'No face detected' : 'Face detected';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Captured frame')),
    body: Column(
      children: [
        Expanded(
          child: YuvFrameView(presenter: _presenter, fit: YuvFrameFit.contain),
        ),
        Text(_result),
        FilledButton(onPressed: _supportsFaceDetection ? detectFace : null, child: const Text('Detect face')),
      ],
    ),
  );
}
