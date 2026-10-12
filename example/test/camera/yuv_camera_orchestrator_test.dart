import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';

import '../support/fake_camera.dart';

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  YuvCameraOrchestrator createOrchestrator({CameraLensDirection lensDirection = CameraLensDirection.front, Duration closeDelay = Duration.zero}) {
    final orchestrator = YuvCameraOrchestrator(lensDirection: lensDirection, closeDelay: closeDelay);
    addTearDown(orchestrator.dispose);
    return orchestrator;
  }

  List<YuvCameraState> recordStates(YuvCameraOrchestrator orchestrator) {
    final states = <YuvCameraState>[];
    orchestrator.addListener(() => states.add(orchestrator.state));
    return states;
  }

  Future<void> untilClosed(YuvCameraOrchestrator orchestrator) async {
    for (int i = 0; i < 100 && orchestrator.state != YuvCameraState.closed; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(orchestrator.state, YuvCameraState.closed);
  }

  // Walks the platform calls and returns the largest number of cameras created and not yet disposed.
  int maxAliveCameras() {
    int alive = 0;
    int maxAlive = 0;
    for (final event in platform.events) {
      if (event.startsWith('create:')) alive++;
      if (event.startsWith('dispose:')) alive--;
      if (alive > maxAlive) maxAlive = alive;
    }
    return maxAlive;
  }

  const front = CameraDescription(name: 'front', lensDirection: CameraLensDirection.front, sensorOrientation: 0);
  const back = CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90);

  test('2a: acquire opens the camera facing lensDirection, else the first one, and reports opening then open', () async {
    platform.cameras = [front, back];
    final orchestrator = createOrchestrator(lensDirection: CameraLensDirection.back);
    final states = recordStates(orchestrator);

    final lease = await orchestrator.acquire();
    await Future<void>.delayed(Duration.zero);

    expect(states, [YuvCameraState.opening, YuvCameraState.open]);
    expect(lease.controller.description.name, 'back');
    expect(lease.controller.value.isInitialized, isTrue);
    expect(orchestrator.controller, same(lease.controller));

    platform.cameras = [front];
    final fallback = await createOrchestrator(lensDirection: CameraLensDirection.external).acquire();
    expect(fallback.controller.description.name, 'front');
  });

  test('2b: acquire during opening waits for the same controller and gets its own lease', () async {
    final orchestrator = createOrchestrator();
    platform.lookupGate = Completer<void>();

    final first = orchestrator.acquire();
    final second = orchestrator.acquire();
    expect(orchestrator.state, YuvCameraState.opening);
    platform.lookupGate?.complete();
    final leases = await Future.wait([first, second]);

    expect(platform.createdCameras, 1);
    expect(leases[0].controller, same(leases[1].controller));
    expect(leases[0], isNot(same(leases[1])));
  });

  test('2c: acquire while open reuses the controller and cancels the delayed close', () async {
    final orchestrator = createOrchestrator(closeDelay: const Duration(milliseconds: 50));
    final first = await orchestrator.acquire();
    final controller = first.controller;
    first.release();

    final second = await orchestrator.acquire();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(orchestrator.state, YuvCameraState.open);
    expect(second.controller, same(controller));
    expect(platform.createdCameras, 1);
    expect(platform.disposedCameras, isEmpty);
  });

  test('2d: releasing the last lease closes the camera at once or after closeDelay', () async {
    final orchestrator = createOrchestrator();
    final notifications = <String>[];
    orchestrator.addListener(() => notifications.add('${orchestrator.state.name}:${orchestrator.controller != null}'));
    final first = await orchestrator.acquire();
    final second = await orchestrator.acquire();

    first.release();
    expect(orchestrator.state, YuvCameraState.open);
    second.release();
    await untilClosed(orchestrator);
    expect(notifications, ['opening:false', 'open:true', 'closing:false', 'closed:false']);
    expect(platform.disposedCameras, [1]);

    final delayed = createOrchestrator(closeDelay: const Duration(milliseconds: 50));
    (await delayed.acquire()).release();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(delayed.state, YuvCameraState.open);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(delayed.state, YuvCameraState.closed);
    expect(platform.disposedCameras, [1, 2]);
  });

  test('2e: acquire during closing waits for the old controller to be disposed before creating a new one', () async {
    final orchestrator = createOrchestrator();
    final first = await orchestrator.acquire();
    platform.disposeGate = Completer<void>();
    first.release();
    expect(orchestrator.state, YuvCameraState.closing);

    final next = orchestrator.acquire();
    await Future<void>.delayed(Duration.zero);
    expect(platform.createdCameras, 1);
    platform.disposeGate?.complete();
    final lease = await next;

    expect(lease.controller.cameraId, 2);
    expect(platform.events.indexOf('dispose:1'), lessThan(platform.events.indexOf('create:2')));
  });

  test('2f: a failed opening disposes the controller, fails every pending acquire and lets the next one retry', () async {
    final orchestrator = createOrchestrator();
    final states = recordStates(orchestrator);
    final failure = CameraException('initFailed', 'Initialization failed.');
    platform.failNextInitialize = failure;
    platform.initializeGate = Completer<void>();

    final first = orchestrator.acquire();
    final second = orchestrator.acquire();
    platform.initializeGate?.complete();

    await expectLater(first, throwsA(same(failure)));
    await expectLater(second, throwsA(same(failure)));
    expect(orchestrator.state, YuvCameraState.closed);
    expect(orchestrator.error, same(failure));
    await Future<void>.delayed(Duration.zero);
    expect(states, [YuvCameraState.opening, YuvCameraState.closed]);
    expect(platform.disposedCameras, [1]);

    final lease = await orchestrator.acquire();
    expect(orchestrator.error, isNull);
    expect(lease.controller.cameraId, 2);

    lease.release();
    await untilClosed(orchestrator);
    platform.cameras = [];
    await expectLater(orchestrator.acquire(), throwsA(isA<CameraException>().having((error) => error.code, 'code', 'noCamera')));
    expect(orchestrator.state, YuvCameraState.closed);
  });

  test('2g: release is idempotent, ignored after dispose, and a released lease has no controller', () async {
    final orchestrator = createOrchestrator();
    final first = await orchestrator.acquire();
    final second = await orchestrator.acquire();

    first.release();
    first.release();

    expect(first.isReleased, isTrue);
    expect(() => first.controller, throwsStateError);
    expect(orchestrator.state, YuvCameraState.open);
    await orchestrator.dispose();
    second.release();
    expect(second.isReleased, isTrue);
    expect(platform.disposedCameras, [1]);
  });

  test('2h: dispose waits for the opening, closes at once, rejects acquire and stops notifying', () async {
    final orchestrator = createOrchestrator(closeDelay: const Duration(hours: 1));
    final states = recordStates(orchestrator);
    platform.initializeGate = Completer<void>();

    final pending = orchestrator.acquire();
    final disposing = orchestrator.dispose();
    expect(orchestrator.dispose(), same(disposing));
    platform.initializeGate?.complete();

    await expectLater(pending, throwsStateError);
    await disposing;
    expect(orchestrator.state, YuvCameraState.closed);
    expect(platform.disposedCameras, [1]);
    expect(states, isEmpty);
    await expectLater(orchestrator.acquire(), throwsStateError);

    final delayed = createOrchestrator(closeDelay: const Duration(hours: 1));
    (await delayed.acquire()).release();
    await delayed.dispose();
    expect(platform.disposedCameras, [1, 2]);
  });

  test('2i: notifications are asynchronous, coalesced and suppressed after dispose', () async {
    final orchestrator = createOrchestrator();
    final states = recordStates(orchestrator);
    platform.lookupGate = Completer<void>();
    final first = orchestrator.acquire();
    final second = orchestrator.acquire();
    expect(orchestrator.state, YuvCameraState.opening);
    expect(states, isEmpty);
    await Future<void>.value();
    expect(states, [YuvCameraState.opening]);
    platform.lookupGate?.complete();
    final leases = await Future.wait([first, second]);
    expect(orchestrator.state, YuvCameraState.open);
    expect(states, [YuvCameraState.opening]);
    leases[0].release();
    platform.disposeGate = Completer<void>();
    leases[1].release();
    expect(orchestrator.controller, isNull);
    expect(orchestrator.state, YuvCameraState.closing);
    expect(states, [YuvCameraState.opening]);
    await Future<void>.delayed(Duration.zero);
    // Open and closing happened before the pending notification; only the current closing state is delivered.
    expect(states, [YuvCameraState.opening, YuvCameraState.closing]);
    platform.disposeGate?.complete();
    await untilClosed(orchestrator);
    expect(maxAliveCameras(), 1);

    final disposed = createOrchestrator();
    final suppressed = recordStates(disposed);
    final pending = disposed.acquire();
    final disposing = disposed.dispose();
    await expectLater(pending, throwsStateError);
    await disposing;
    expect(suppressed, isEmpty);
  });

  test('50 overlapping acquire and release cycles leave every controller disposed once', () async {
    final orchestrator = createOrchestrator();

    await Future.wait([
      for (int i = 0; i < 50; i++)
        () async {
          // Different microtask offsets make the cycles meet the camera opening, open and closing.
          for (int k = 0; k < i * 3; k++) {
            await Future<void>.value();
          }
          (await orchestrator.acquire()).release();
        }(),
    ]);
    await untilClosed(orchestrator);

    expect(platform.createdCameras, platform.disposedCameras.length);
    expect(platform.disposedCameras.toSet(), hasLength(platform.disposedCameras.length));
    expect(platform.overlappingStarts, isEmpty);
    expect(orchestrator.error, isNull);
    expect(maxAliveCameras(), 1);
  });
}
