# Getting started

**Task:** show a live camera preview in a Flutter app.

**Conditions:** Dart 3.12 / Flutter 3.44 or later, and a device or desktop with a camera. The platform setup below is
required before the camera can open. This page ends with a preview; capturing a frame is in
[Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture), and the README Quick start shows a
complete app with a capture button.

## Step 1: add the packages

```yaml
dependencies:
  yuv_camera: ^0.0.1
  yuv_ffi: ^0.5.2
  camera: ^0.12.1
  # Windows, macOS, and Linux only:
  camera_desktop: ^2.0.0
```

`yuv_camera` requires `yuv_ffi: ^0.5.2` and works with `camera` 0.11 and 0.12. You use `yuv_ffi` types such as
`YuvImage` with it. `camera_desktop` is not a dependency of `yuv_camera`: your app adds it next to `camera` on desktop
platforms.

## Step 2: set up the platform

| Platform | What to do |
| --- | --- |
| Android | Set `minSdk` to 26 or higher (`yuv_ffi` requires API 26). The `camera` plugin asks for the camera permission at run time. |
| iOS | Add `NSCameraUsageDescription` with a short reason to `ios/Runner/Info.plist`. |
| macOS | Add `NSCameraUsageDescription` to `Info.plist` and the `com.apple.security.device.camera` entitlement to each entitlements file you ship. |
| Windows | Add `camera_desktop`. Nothing else is needed. |
| Linux | Add `camera_desktop` and install the GStreamer development libraries (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`). |
| Web | Use Chrome over `localhost` or HTTPS and allow the camera in the browser. |

Permission details belong to the plugins; their documentation is the primary source:
[`camera`](https://pub.dev/packages/camera) and [`camera_desktop`](https://pub.dev/packages/camera_desktop). More on each
platform, and what is verified, is in
[Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting).

## Step 3: write the app

This complete `lib/main.dart` initializes `yuv_ffi`, opens the first camera and shows the preview.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(home: PreviewPage()));
}

class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  CameraController? _controller;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _problem = 'This device reports no camera.');
        return;
      }
      controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      await controller?.dispose();
      if (mounted) setState(() => _problem = 'The camera could not be opened: $error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_problem != null) return Scaffold(body: Center(child: Text(_problem!)));
    if (controller == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(body: YuvCameraView(cameraController: controller));
  }
}
```

What each part does:

- `YuvFfi.initialize()` prepares `yuv_ffi`; await it before the first frame arrives.
- `availableCameras()` can return an empty list, and `CameraController.initialize()` throws when the user denies the
  permission or the camera is busy. Both end in a message here instead of an exception that nobody catches.
- Every `await` is followed by a `mounted` check, and a controller that finishes initializing after the page was closed is
  disposed at once. You own the controller: `YuvCameraView` never disposes it.
- `YuvCameraView` needs an initialized `CameraController`. It opens its own frame stream, converts frames into
  `YuvImage`s and draws them through the `yuv_ffi` frame presenter. By default the frame fills the available space and is
  cropped to fit (`fit: YuvFrameFit.cover`).
- While a native YUV source is active, it owns frame delivery for that controller. Do not also call `startImageStream`,
  start video recording with `onAvailable`, or subscribe to platform frames directly.

## Expected result

After the permission is granted the screen shows the live camera picture, filling the screen. If the permission is
denied or no camera exists, the screen shows a one-line message instead of a preview.

## Limits and errors

| Symptom | Cause and action |
| --- | --- |
| "This device reports no camera." | `availableCameras()` returned an empty list: the device reports no camera. |
| "The camera could not be opened: ..." | `initialize()` threw. Read the message: a denied permission needs the platform setup above and the user's consent; a busy camera needs the other app closed. |
| The screen shows `Camera error: ...` where the preview should be | `YuvCameraView` received a stream error and stopped. See [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting). |
| `UnsupportedError` (on Web sometimes `StateError`) saying `YuvFfi.initialize()` must complete | A call on a frame, such as `frame.upright()`, ran before `YuvFfi.initialize()` finished. Await it in `main` before `runApp`. |
| The build fails on Linux | The GStreamer development libraries are missing. |

## Related pages

- [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): capture, switch cameras, dispose in the right order.
- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): do something with each frame.
- [yuv_ffi Getting started](https://github.com/Anfet/yuv_ffi/wiki/Getting-started): what you can do with the images the camera delivers.
