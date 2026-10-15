# Sharing the camera

**Task:** show the same camera on several screens, open it only while a screen needs it, and close it when the last
screen leaves, without creating and disposing a `CameraController` yourself.

**Conditions:** the packages and platform setup from
[Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started). You do not need to call
`availableCameras()` or create a `CameraController`: the orchestrator does both. Use
[Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture) instead when one screen owns its
controller.

## The four pieces

| Type | What it is |
| --- | --- |
| `YuvCameraOrchestrator` | Owns the single camera of the app. It is a `ChangeNotifier`: it reports `state`, `controller` and `error`. |
| `YuvCameraLease` | A claim on the open camera, returned by `acquire()`. It has the initialized `controller` and a `release()`. |
| `YuvCameraState` | `closed`, `opening`, `open` or `closing`: the lifecycle of the camera controller. |
| `YuvCameraLeaseBuilder` | A widget that acquires a lease while it is mounted and the app is visible, builds your child with the controller and releases the lease for you. |

## How the camera is opened and closed

- The first lease opens the camera: the orchestrator looks up the cameras, picks the first one facing `lensDirection`
  (`CameraLensDirection.front` by default, or the first camera when none faces that way), creates a `CameraController`
  with `resolution` (`ResolutionPreset.medium` by default) and the optional `fps`, without audio, and initializes it.
- Releasing the last lease closes the camera after `closeDelay`, which is zero by default. A lease taken within that
  delay keeps the same controller.
- Everything happens one step after another, so at most one controller is alive. A request made while the camera is
  closing waits for the old controller to be disposed and then opens a new one. Several concurrent `acquire()` calls
  share one opening.
- Listeners are told in a microtask, and one notification can cover several transitions in the same turn. The getters
  change at once, so read the current `state` inside the listener. No notification arrives after `dispose()`.

## Show one camera on two screens

The owner of the orchestrator (usually your app or a top-level widget) creates it once and disposes it once. Each screen
puts `YuvCameraLeaseBuilder` around the widget that needs the controller.

```dart
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// Owns one orchestrator and shows two camera previews at once.
class SharedCameraApp extends StatefulWidget {
  const SharedCameraApp({super.key});

  @override
  State<SharedCameraApp> createState() => _SharedCameraAppState();
}

class _SharedCameraAppState extends State<SharedCameraApp> {
  final YuvCameraOrchestrator _orchestrator = YuvCameraOrchestrator(closeDelay: const Duration(seconds: 2));
  bool _showFirstPreview = true;
  bool _showSecondPreview = true;

  @override
  void dispose() {
    _orchestrator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Shared camera')),
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (_showFirstPreview) Expanded(child: CameraPanel(orchestrator: _orchestrator)),
                  if (_showSecondPreview) Expanded(child: CameraPanel(orchestrator: _orchestrator)),
                ],
              ),
            ),
            ListenableBuilder(listenable: _orchestrator, builder: (context, child) => Text('Camera: ${_orchestrator.state.name}')),
            Wrap(
              children: [
                FilledButton(
                  onPressed: () => setState(() => _showFirstPreview = !_showFirstPreview),
                  child: Text(_showFirstPreview ? 'Remove first preview' : 'Show first preview'),
                ),
                FilledButton(
                  onPressed: () => setState(() => _showSecondPreview = !_showSecondPreview),
                  child: Text(_showSecondPreview ? 'Remove second preview' : 'Show second preview'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A preview of the shared camera; the camera opens when this widget is mounted.
class CameraPanel extends StatelessWidget {
  const CameraPanel({super.key, required this.orchestrator});

  final YuvCameraOrchestrator orchestrator;

  @override
  Widget build(BuildContext context) {
    return YuvCameraLeaseBuilder(
      orchestrator: orchestrator,
      builder: (context, controller) => YuvCameraView(cameraController: controller),
    );
  }
}

```

Expected result: both panels are visible together. The orchestrator opens one camera controller and both
`YuvCameraView` widgets use it. Choose **Remove second preview**: that panel's lease is released while the first preview
remains visible and the camera stays open. Then choose **Remove first preview**: the final lease is released, then
after the two-second `closeDelay` the state goes through `closing` to `closed`. If a preview is added during that delay,
the existing camera remains open. This recipe was compiled and analyzed for Windows and Web; it has not run on a
physical camera, so test it on your target devices.

## What `YuvCameraLeaseBuilder` does for you

- It acquires a lease in `initState` and again whenever the app is shown, and builds your `builder` with
  `lease.controller`. While the camera opens, and after a failure, it shows a progress indicator or a message with a
  Retry button. Pass `placeholderBuilder: (context, error, retry) => ...` to draw your own: `error` is the failure of the
  last attempt, or `null` while opening or hidden, and `retry` starts a new attempt after a failure (it does nothing
  while hidden, opening or already leased).
- It releases the lease when the app is hidden (`AppLifecycleState.hidden`), when the widget is disposed and when you
  pass a different orchestrator. `inactive` does not release it, so camera permission prompts on Android do not
  interrupt opening.
- It removes the child before releasing the lease, so the frame stream of a `YuvCameraView` or `YuvTransformView`
  stops before the camera closes.
- The child can be a `YuvCameraView`, a `YuvTransformView` or any widget that uses the `CameraController`.

When a controller or its YUV frame stream fails, the orchestrator invalidates its current leases and waits for frame
subscription cancellation before disposing the controller. The builder removes the preview and shows Retry; retry opens
a new controller without requiring route navigation. A manually managed lease owner should likewise reacquire after a
terminal failure.

While a native YUV source is active, it exclusively owns frame streaming for that controller. Do not also call
`startImageStream`, start video recording with `onAvailable`, or subscribe to platform frames directly. An already active
image stream is rejected, but later external starts cannot be intercepted reliably.

## Without the builder

Call `acquire()` yourself when a non-widget needs the camera, and always release:

```dart
import 'package:camera/camera.dart';
import 'package:yuv_camera/yuv_camera.dart';

Future<void> useCamera(YuvCameraOrchestrator orchestrator) async {
  final lease = await orchestrator.acquire();
  try {
    final controller = lease.controller; // an initialized CameraController
    // ... use controller ...
    await controller.setFlashMode(FlashMode.off);
  } finally {
    lease.release();
  }
}
```

`release()` is safe to call twice. `lease.controller` throws a `StateError` after `release()`. The orchestrator does not
watch the app lifecycle, so release manually acquired leases yourself when the app goes to the background.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| `acquire()` throws `CameraException` with code `noCamera`, or the builder shows `Camera unavailable: ...` | The device reports no camera. Check that a camera is connected and, on desktop, that `camera_desktop` is in `pubspec.yaml`. The orchestrator is `closed` again and keeps the failure in `error`; the next `acquire()` or Retry tries again. |
| `Bad state: The camera lease was released.` | You read `lease.controller` after `release()`. Keep the lease for as long as you use the controller, or build from `YuvCameraLeaseBuilder`, which hands the controller only while the lease is held. |
| `Bad state: The camera orchestrator was disposed.` | `dispose()` rejects new `acquire()` calls and completes the waiting ones with this error. Dispose the orchestrator only when no screen needs it any more. |
| The camera stays open after the app goes to the background | A lease acquired by hand is not released automatically. Release it when the app is hidden, or use `YuvCameraLeaseBuilder`. |
| The camera closes and reopens when you move between screens | The last lease was released and `closeDelay` passed (zero by default). Raise `closeDelay` or hold a lease across the navigation. |
| `initialize()` fails because the permission was denied | The failure is reported as `error`, and the builder shows it. After the user grants the permission, Retry opens the camera. |

## Related pages

- [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): a view you own, capture and the view controller.
- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): handle frames of the shared camera with `onFrame`.
- [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting): permissions and desktop setup.
- The example app's [Open & close screen](https://github.com/Anfet/yuv_camera/blob/main/example/lib/orchestrator/orchestrator_screen.dart).
