import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const _DeviceCheckApp());
}

class _DeviceCheckApp extends StatefulWidget {
  const _DeviceCheckApp();

  @override
  State<_DeviceCheckApp> createState() => _DeviceCheckAppState();
}

class _DeviceCheckAppState extends State<_DeviceCheckApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: DeviceCheckScreen(orchestrator: _orchestrator));
  }

  @override
  void dispose() {
    _orchestrator.dispose().ignore();
    super.dispose();
  }

  final YuvCameraOrchestrator _orchestrator = YuvCameraOrchestrator(lensDirection: CameraLensDirection.front, fps: 30);
}
