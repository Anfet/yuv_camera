import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera_example/camera_screen.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';
import 'package:yuv_camera_example/main.dart';

import 'support/fake_camera.dart';

void main() {
  setUp(() => CameraPlatform.instance = FakeCameraPlatform());

  testWidgets('Take photo opens the camera screen', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CameraScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Device check opens the device check screen', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Device check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DeviceCheckScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
