import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: DeviceCheckScreen()));
}
