import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/home_screen.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MainApp());
}

/// The example app. It owns the one [YuvCameraOrchestrator] that every screen takes its camera from.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6B64))),
      home: HomeScreen(orchestrator: _orchestrator),
    );
  }

  @override
  void dispose() {
    _orchestrator.dispose().ignore();
    super.dispose();
  }

  final YuvCameraOrchestrator _orchestrator = YuvCameraOrchestrator(lensDirection: CameraLensDirection.front, fps: 30);
}
