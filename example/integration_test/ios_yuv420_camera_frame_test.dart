import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports the iOS two-plane yuv420 NV12 fixture', (tester) async {
    await YuvFfi.initialize();
    // ignore: deprecated_member_use
    final cameraImage = CameraImage.fromPlatformData(<dynamic, dynamic>{
      'format': 875704438,
      'width': 3,
      'height': 3,
      'planes': <Map<dynamic, dynamic>>[
        <dynamic, dynamic>{
          'bytes': Uint8List.fromList([82, 82, 82, 0xee, 82, 82, 82, 0xee, 82, 82, 82]),
          'bytesPerRow': 4,
          'bytesPerPixel': null,
          'width': 3,
          'height': 3,
        },
        <dynamic, dynamic>{
          'bytes': Uint8List.fromList([90, 240, 54, 34, 0xee, 90, 240, 54, 34]),
          'bytesPerRow': 5,
          'bytesPerPixel': null,
          'width': 2,
          'height': 2,
        },
      ],
    });

    final image = importCameraImage(cameraImage);
    expect(image.format, YuvPixelFormat.nv12);
    expect(image.uPlane.pixelStride, 2);
    expect(image.uPlane.rowStride, 5);
    expect(image.toBgraBytes().take(4), [0, 1, 255, 255]);
  });
}
