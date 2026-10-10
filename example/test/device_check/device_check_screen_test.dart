import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera_example/device_check/device_check_report.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';

void main() {
  testWidgets('skip completes every step and copies the final JSON', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));

    for (int index = 0; index < 7; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    expect(find.text('Device check result'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, contains('"card": "DEVICE-1"'));
  });

  testWidgets('a question step records the selected answer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump(deviceCheckMeasurementDuration);
    await tester.pump();
    await tester.tap(find.text('Yes'));
    await tester.pump();

    for (int index = 0; index < 4; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.textContaining('"answer": true'), findsOneWidget);
  });

  testWidgets('the final capture step waits for an answer before showing its result', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));

    for (int index = 0; index < 6; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    await tester.tap(find.text('Capture'));
    await tester.pump();

    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Device check result'), findsNothing);

    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(find.text('Device check result'), findsOneWidget);
    final json = tester.widget<SelectableText>(find.byType(SelectableText)).data;
    if (json == null) fail('The final report must contain JSON text.');
    final steps = jsonDecode(json)['steps'] as List<Object?>;
    final capture = steps.last as Map<String, Object?>;
    expect(capture['answer'], isTrue);
  });

  testWidgets('the check screen does not use an app bar in landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Hold the phone vertically.'), findsOneWidget);
  });
}
