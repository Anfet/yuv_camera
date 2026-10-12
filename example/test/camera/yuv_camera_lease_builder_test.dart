import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/yuv_camera.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;

  // The host frames are mirrored on Windows, so capture() crops through the native backend.
  setUpAll(YuvFfi.initialize);

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  // Orchestrators are not disposed in tearDown: after a failed test the tree is still mounted and closing its camera
  // would wait for fake-clock microtasks that no longer run.

  // The fake camera answers in microtasks; real time lets the frame source start its stream.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> pumpView(
    WidgetTester tester,
    YuvCameraOrchestrator orchestrator, {
    YuvCameraViewController? viewController,
    VoidCallback? onStreamStopped,
  }) => tester.pumpWidget(
    MaterialApp(
      home: YuvCameraLeaseBuilder(
        orchestrator: orchestrator,
        builder: (context, controller) =>
            YuvCameraView(cameraController: controller, viewController: viewController, onStreamStopped: onStreamStopped),
      ),
    ),
  );

  testWidgets('shows the leased camera frames once the camera is open', (tester) async {
    final viewController = YuvCameraViewController();
    addTearDown(viewController.dispose);
    await pumpView(tester, YuvCameraOrchestrator(), viewController: viewController);
    await settle(tester);

    YuvImage? captured;
    viewController.capture().then((image) => captured = image).ignore();
    platform.emit(platform.listens.single, cameraFrame(40));
    await pumpUntil(tester, () => captured != null, reason: 'the drawn frame');

    expect(captured, isA<YuvImage>().having(shadeOfYuv, 'shade', 40));
  });

  testWidgets('removing the view stops the frame stream before the camera is disposed', (tester) async {
    final orchestrator = YuvCameraOrchestrator();
    await pumpView(tester, orchestrator);
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);

    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.events, containsAllInOrder(['listen:1', 'cancel:1', 'dispose:1']));
  });

  testWidgets('a view removed while the camera opens releases the late lease', (tester) async {
    final orchestrator = YuvCameraOrchestrator();
    platform.initializeGate = Completer<void>();
    await pumpView(tester, orchestrator);
    await tester.pump();
    expect(orchestrator.state, YuvCameraState.opening);

    await tester.pumpWidget(const SizedBox());
    platform.initializeGate?.complete();
    await settle(tester);

    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.disposedCameras, [1]);
  });

  testWidgets('an opening failure is shown in place of the preview', (tester) async {
    platform.failNextInitialize = CameraException('initFailed', 'Initialization failed.');
    await pumpView(tester, YuvCameraOrchestrator());
    await settle(tester);

    expect(find.textContaining('Camera unavailable:'), findsOneWidget);
  });

  testWidgets('switching orchestrators stops the old stream before the old camera is disposed', (tester) async {
    final first = YuvCameraOrchestrator();
    final statesAtStop = <YuvCameraState>[];
    await pumpView(tester, first, onStreamStopped: () => statesAtStop.add(first.state));
    await settle(tester);

    await pumpView(tester, YuvCameraOrchestrator());
    await settle(tester);

    expect(statesAtStop, isEmpty);
    expect(first.state, YuvCameraState.closed);
    expect(platform.events, containsAllInOrder(['listen:1', 'cancel:1', 'dispose:1']));
    expect(platform.isStreaming(2), isTrue);
  });
  testWidgets('Retry opens the camera after failure without remounting', (tester) async {
    final orchestrator = YuvCameraOrchestrator();
    platform.failNextInitialize = CameraException('initFailed', 'Initialization failed.');
    await pumpView(tester, orchestrator);
    await settle(tester);
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(orchestrator.error, isNull);
    expect(platform.isStreaming(2), isTrue);
    expect(find.textContaining('Camera unavailable:'), findsNothing);
  });

  testWidgets('custom retry clears the error and ignores repeated or already leased requests', (tester) async {
    final orchestrator = YuvCameraOrchestrator();
    platform.failNextInitialize = CameraException('initFailed', 'Initialization failed.');
    VoidCallback? retry;
    Object? shownError;
    await tester.pumpWidget(
      MaterialApp(
        home: YuvCameraLeaseBuilder(
          orchestrator: orchestrator,
          builder: (context, controller) => YuvCameraView(cameraController: controller),
          placeholderBuilder: (context, error, callback) {
            shownError = error;
            retry = callback;
            return const SizedBox();
          },
        ),
      ),
    );
    await settle(tester);
    expect(shownError, isA<CameraException>());
    platform.initializeGate = Completer<void>();
    retry?.call();
    retry?.call();
    await tester.pump();
    expect(shownError, isNull);
    expect(platform.createdCameras, 2);
    platform.initializeGate?.complete();
    await settle(tester);
    retry?.call();
    await settle(tester);
    expect(platform.createdCameras, 2);
  });

  testWidgets('hidden releases the lease after stopping the stream; resumed opens it again', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final orchestrator = YuvCameraOrchestrator();
    await pumpView(tester, orchestrator);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    expect(platform.isStreaming(1), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);
    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.events, containsAllInOrder(['listen:1', 'cancel:1', 'dispose:1']));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(platform.isStreaming(2), isTrue);
  });

  testWidgets('a lease completing while hidden is released before showing the app again', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    platform.initializeGate = Completer<void>();
    final orchestrator = YuvCameraOrchestrator();
    await pumpView(tester, orchestrator);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    platform.initializeGate?.complete();
    await settle(tester);
    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.listens, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(platform.isStreaming(2), isTrue);
  });

  for (final above in [true, false]) {
    testWidgets('ListenableBuilder ${above ? 'above' : 'beside'} the lease builder survives insert and remove', (tester) async {
      final orchestrator = YuvCameraOrchestrator();
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      final states = <YuvCameraState>[];
      platform.initializeGate = Completer<void>();
      final camera = ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, visible, child) => visible
            ? YuvCameraLeaseBuilder(
                orchestrator: orchestrator,
                builder: (context, controller) => YuvCameraView(cameraController: controller),
              )
            : const SizedBox(),
      );
      final listener = ListenableBuilder(
        listenable: orchestrator,
        child: above ? camera : null,
        builder: (context, child) {
          states.add(orchestrator.state);
          return above ? child ?? const SizedBox() : const SizedBox();
        },
      );
      await tester.pumpWidget(MaterialApp(home: above ? listener : Stack(children: [listener, camera])));
      shown.value = true;
      await tester.pump();
      await tester.pump();
      platform.initializeGate?.complete();
      await settle(tester);
      platform.disposeGate = Completer<void>();
      shown.value = false;
      await tester.pump();
      await tester.pump();
      platform.disposeGate?.complete();
      await settle(tester);
      expect(
        states,
        containsAllInOrder([YuvCameraState.closed, YuvCameraState.opening, YuvCameraState.open, YuvCameraState.closing, YuvCameraState.closed]),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
