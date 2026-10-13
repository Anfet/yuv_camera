import 'dart:async';
import 'dart:convert';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_camera_example/device_check/device_check_report.dart';
import 'package:yuv_camera_example/device_check/device_check_screen.dart';

import '../support/fake_camera.dart';

void main() {
  testWidgets('skip completes every step and shares the final JSON', (tester) async {
    Map<Object?, Object?>? shared;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') shared = call.arguments as Map<Object?, Object?>;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, null));
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckScreen(cameraEnabled: false)));

    expect(find.text('Start'), findsOneWidget);
    for (int index = 0; index < 5; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.text('Next'), findsOneWidget);
    for (int index = 0; index < 2; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    expect(find.text('Device check result'), findsOneWidget);
    final json = tester.widget<SelectableText>(find.byType(SelectableText)).data;
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(shared?['text'], json);
    expect(shared?['title'], 'Device check result');
    expect(find.text('Copy'), findsNothing);
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
    expect(find.text('Is the preview upright, with your head at the top of the screen?'), findsOneWidget);
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

    expect(find.text('Does the captured frame in the corner match the preview: same rotation, same mirror side, same framing?'), findsOneWidget);
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
    expect(find.text('Hold the phone upright with the front camera facing you. Tap Start and hold still.'), findsOneWidget);

    for (int index = 0; index < 6; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    await tester.tap(find.text('Capture'));
    await tester.pump();

    expect(find.text('Does the captured frame in the corner match the preview: same rotation, same mirror side, same framing?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the camera goes back to the orchestrator after the last step', (tester) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final orchestrator = YuvCameraOrchestrator();
    await tester.pumpWidget(MaterialApp(home: DeviceCheckScreen(orchestrator: orchestrator)));
    await settleCamera(tester);
    expect(orchestrator.state, YuvCameraState.open);

    for (int index = 0; index < 7; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    await settleCamera(tester);

    expect(find.text('Device check result'), findsOneWidget);
    expect(platform.disposedCameras, [1]);
    expect(orchestrator.state, YuvCameraState.closed);
  });

  testWidgets('a camera that opens after the last step is given back while the result is shown', (tester) async {
    final platform = FakeCameraPlatform()..initializeGate = Completer<void>();
    CameraPlatform.instance = platform;
    final orchestrator = YuvCameraOrchestrator();
    await tester.pumpWidget(MaterialApp(home: DeviceCheckScreen(orchestrator: orchestrator)));
    await settleCamera(tester);
    expect(orchestrator.state, YuvCameraState.opening);

    for (int index = 0; index < 7; index++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.text('Device check result'), findsOneWidget);

    platform.initializeGate!.complete();
    await settleCamera(tester);

    expect(find.text('Device check result'), findsOneWidget);
    expect(platform.createdCameras, greaterThan(0));
    expect(platform.disposedCameras, hasLength(platform.createdCameras));
    expect(orchestrator.state, YuvCameraState.closed);
  });
}
