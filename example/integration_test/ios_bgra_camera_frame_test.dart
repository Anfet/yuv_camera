import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_image_import.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preserves each visible pixel of a padded iOS BGRA camera frame', (tester) async {
    await YuvFfi.initialize();

    // Two rows of two BGRA pixels. Each row has four padding bytes, which
    // must never be interpreted as a third pixel or shift the second row.
    // The fixture uses the plugin's only public constructor available through
    // package:camera; it models the legacy iOS CameraImage payload exactly.
    // ignore: deprecated_member_use
    final cameraImage = CameraImage.fromPlatformData(<dynamic, dynamic>{
      'format': 1111970369, // kCVPixelFormatType_32BGRA
      'width': 2,
      'height': 2,
      'planes': <Map<dynamic, dynamic>>[
        <dynamic, dynamic>{
          'bytes': Uint8List.fromList(<int>[
            0x01, 0x02, 0x03, 0xff, // pixel (0, 0)
            0x11, 0x12, 0x13, 0xff, // pixel (1, 0)
            0xaa, 0xbb, 0xcc, 0xdd, // row padding
            0x21, 0x22, 0x23, 0xff, // pixel (0, 1)
            0x31, 0x32, 0x33, 0xff, // pixel (1, 1)
            0xee, 0xff, 0x00, 0x99, // row padding
          ]),
          'bytesPerRow': 12,
          // This mirrors the iOS camera plugin: its packed-plane BPP is not
          // available to the public Dart CameraImage API.
          'bytesPerPixel': null,
          'height': 2,
          'width': 2,
        },
      ],
    });

    final yuv = importCameraImage(cameraImage);

    expect(yuv.format, YuvPixelFormat.bgra8888);
    expect(yuv.yPlane.pixelStride, 4);
    expect(yuv.yPlane.rowStride, 12);
    expect(yuv.toBgraBytes(), orderedEquals(<int>[0x01, 0x02, 0x03, 0xff, 0x11, 0x12, 0x13, 0xff, 0x21, 0x22, 0x23, 0xff, 0x31, 0x32, 0x33, 0xff]));
  });
}
