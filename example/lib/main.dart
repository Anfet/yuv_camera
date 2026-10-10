import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/camera_screen.dart';
import 'package:yuv_camera_example/capture_result_screen.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('YUV Camera')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: _takePhoto, child: const Text('Take photo')),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DeviceCheckScreen())),
                child: const Text('Device check'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final frame = await Navigator.of(context).push<YuvImage>(MaterialPageRoute(builder: (_) => const CameraScreen()));
    if (!mounted || frame == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => CaptureResultScreen(image: frame)));
  }
}
