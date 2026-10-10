# yuv_camera

`yuv_camera` shows a live camera preview in Flutter, hands each camera frame to
your code as a `YuvImage`, and captures the frame that is actually on screen.
Use it for camera screens that process frames (face detection, filters,
measurements) or take a picture of what the user sees. It is built on the
[`camera`](https://pub.dev/packages/camera) plugin and
[`yuv_ffi`](https://github.com/Anfet/yuv_ffi), and has no native plugin,
platform channel, or FFI layer of its own.

## Which package do you need

| You want to | Use |
| --- | --- |
| Show a camera preview, process frames in `onFrame`, or capture a frame | `yuv_camera` (this package) |
| Create, convert, transform, or display YUV/BGRA images without a camera | [`yuv_ffi`](https://github.com/Anfet/yuv_ffi) alone |

`yuv_camera` depends on `yuv_ffi`, so you use `yuv_ffi` types such as `YuvImage`
with it; `yuv_ffi` never depends on `yuv_camera`.

## Installation

```yaml
dependencies:
  yuv_camera: ^0.0.1
  yuv_ffi: ^0.5.2
  camera: ^0.11.0+2
  # Windows, macOS, and Linux only:
  camera_desktop: ^2.0.0
```

Requirements: Dart `^3.12.0`, Flutter `>=3.44.0`. `yuv_camera` requires
`yuv_ffi: ^0.5.2`. Until that version is published, see Local development
below.

### Platform setup

- **Android:** the `camera` plugin requests the camera permission at run time.
  `yuv_ffi` requires Android API 26, so set `minSdk` to 26 or higher.
- **iOS:** add `NSCameraUsageDescription` with a short reason to
  `ios/Runner/Info.plist`.
- **Windows, macOS, Linux:** add `camera_desktop` next to `camera`.
  `yuv_camera` does not depend on it or register it. macOS needs
  `NSCameraUsageDescription` and the `com.apple.security.device.camera`
  entitlement in each entitlements file you ship. Linux builds need the
  GStreamer development libraries
  (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`).
- **Web:** Chrome over localhost or HTTPS, with the browser's camera
  permission. Frames come from `MediaStreamTrackProcessor`, with a canvas
  fallback.

The plugins' own documentation is the primary source for permission details:
[`camera`](https://pub.dev/packages/camera) and
[`camera_desktop`](https://pub.dev/packages/camera_desktop).

## Quick start

This complete `lib/main.dart` initializes `yuv_ffi`, finds a camera, shows the
preview, and captures the visible frame.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(home: CameraPage()));
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _viewController = YuvCameraViewController();
  CameraController? _camera;
  Object? _error;
  YuvImage? _captured;

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  Future<void> _openCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera is available.');
        return;
      }
      controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize(); // Throws if permission is denied.
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (error) {
      await controller?.dispose();
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _capture() async {
    final image = await _viewController.capture();
    if (!mounted) return;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing was captured.')));
      return;
    }
    setState(() => _captured = image);
  }

  @override
  void dispose() {
    _viewController.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final Widget body;
    if (_error != null) {
      body = Center(child: Text('Camera unavailable: $_error'));
    } else if (camera == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          YuvCameraView(cameraController: camera, viewController: _viewController),
          if (_captured case final image?)
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(width: 120, height: 160, child: YuvImageWidget(image: image)),
            ),
        ],
      );
    }
    return Scaffold(
      body: body,
      floatingActionButton: camera == null ? null : FloatingActionButton(onPressed: _capture, child: const Icon(Icons.camera)),
    );
  }
}
```

What the example does:

- `YuvFfi.initialize()` prepares `yuv_ffi`; call it before the first frame.
- `availableCameras()` can return an empty list, and `initialize()` throws when
  the user denies the permission; both end in a message instead of a preview.
- Every `await` is followed by a `mounted` check, and a controller created
  after the page was closed is disposed immediately.
- `YuvCameraView` needs an initialized `CameraController` and draws it through
  the `yuv_ffi` frame presenter. You own the controller and dispose it.
- `capture()` returns the next frame that is actually drawn, cropped to what is
  visible, or `null` if the view is not attached or stops first.

## Main actions

| Action | API |
| --- | --- |
| Show a preview | `YuvCameraView(cameraController: ...)`; `fit` and `alignment` choose how the frame fills the space |
| Process frames | `onFrame` receives a `YuvCameraFrame` at most once per `onFrameInterval` (default 200 ms) and never concurrently with itself; errors it throws go to `FlutterError.reportError` |
| Capture a picture | `YuvCameraViewController.capture()` |
| Draw over the preview | `overlayBuilder` receives the `YuvFrameGeometry` of the displayed frame; `viewController.geometry` exposes it too |
| Change each frame before it is drawn | `YuvTransformView(transform: ...)` |
| Read every frame yourself | `YuvCameraFrameSource` (`start`, `stop`, `dispose`); it delivers all frames and leaves throttling to you |

Everything is exported from `package:yuv_camera/yuv_camera.dart`. A
`YuvCameraFrame` has `width`, `height`, `format`, `orientation`, `timestamp`,
`image` (the raw camera image, imported on first access) and `upright()`
(packed and oriented, cached).

Ownership: a frame and its `image` and `upright()` images belong to the
delivery and must not be mutated. Call `copy()` before an in-place operation:

```dart
onFrame: (frame) {
  final working = frame.upright().copy()..applyGrayscale();
  // Use working; the delivered frame is unchanged.
},
```

The image returned by `capture()` is a new image owned by your code. Heavy
synchronous work in `onFrame` blocks the UI isolate and stops painting.

### Processing frames with ML Kit

ML Kit is not a dependency of this package. Pass an `onFrame` handler and
convert the frame in your application; the example (`example/lib/ext.dart`,
`toInputImage`) packs a `YuvImage` into an `InputImage` for
`google_mlkit_face_detection` and applies the frame's `orientation.rotation`.

## Platforms and limits

Backend availability, building, and a confirmed physical camera are different
things. The checks run directly on the maintainer's machines with the scripts
in `tool/ci/` (the repository has no hosted CI), and their results are recorded
against exact commits. From the package root: `pwsh -File tool/ci/vm.ps1`,
`windows.ps1`, `android.ps1`, `web.ps1`, and `example.ps1` on Windows;
`bash tool/ci/linux.sh` on Linux; `bash tool/ci/macos.sh` and
`bash tool/ci/ios.sh` on macOS. So far they have confirmed:

- 34 example tests (26 camera, 5 device-check, 3 `toInputImage`).
- The native capture integration target on Windows (Release) and on the Android
  `Tablet` emulator (x86_64, API 35).
- The Web camera source smoke in Chrome (JavaScript) with a fake media stream.
- The iOS observation in the `YuvCameraFrame` documentation: one iPhone,
  iOS 18.7, front camera, portrait and landscape.

A build or a passing emulator or fake-stream target does not prove that a
physical camera works on that platform. Other platforms, browsers (including
Safari and Firefox), `--wasm` builds, and devices are not claimed.

## Learn more

- [Example app](example/README.md): a camera screen with capture, an ML Kit
  face-detection screen, and a device-check screen.
- [API reference](https://pub.dev/documentation/yuv_camera/latest/) for every
  public class and parameter.
- [CHANGELOG.md](CHANGELOG.md).
- [`yuv_ffi`](https://github.com/Anfet/yuv_ffi) for images, operations, and
  geometry.

## Local development with an unpublished `yuv_ffi`

Until the matching `yuv_ffi` is published, the pair resolves only through ignored local overrides. Create
`pubspec_overrides.yaml` in the package root and in `example/` (both are in `.gitignore`):

```yaml
dependency_overrides:
  yuv_ffi:
    path: ../yuv_ffi
```

(`../../yuv_ffi` in `example/`). To check an exact pair of commits, run from the package root:

```text
pwsh -File tool/check_pair.ps1 -CameraPath <camera-checkout> -CameraSha <full-camera-sha> -YuvPath <yuv-checkout> -YuvSha <full-yuv-sha>
```

The script compares both checkouts with the expected SHAs and requires clean tracked files before any `pub get`, creates
its own overrides (it stops without touching them if an override already exists), runs analyze, the example tests and
the Windows and Web targets, and removes its overrides afterwards. It never switches branches.

## License

MIT, see [LICENSE](LICENSE).
