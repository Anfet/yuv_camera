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
  camera: ^0.12.1
  # Windows, macOS, and Linux only:
  camera_desktop: ^2.0.0
```

Requirements: Dart `^3.12.0`, Flutter `>=3.44.0`. `yuv_camera` requires
`yuv_ffi: ^0.5.2` and works with `camera` 0.11 and 0.12.

### Platform setup

- **Android:** the `camera` plugin requests the camera permission at run time.
  `yuv_ffi` requires Android API 26, so set `minSdk` to 26 or higher.
- **iOS:** add `NSCameraUsageDescription` with a short reason to
  `ios/Runner/Info.plist`. `yuv_ffi` requires iOS 13 or later.
- **Windows, macOS, Linux:** add `camera_desktop` next to `camera`.
  `yuv_camera` does not depend on it or register it. macOS 10.15 or later
  (required by `yuv_ffi`) needs
  `NSCameraUsageDescription` and the `com.apple.security.device.camera`
  entitlement in each entitlements file you ship. Linux builds need the
  GStreamer development libraries
  (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`).
- **Web:** Chrome over localhost or HTTPS, with the browser's camera
  permission. `yuv_camera` opens a second stream on the controller's device,
  selected by its unique, non-empty camera label; empty, missing or duplicate
  labels fall back to the camera direction. The controller's `ResolutionPreset`
  and optional `fps` are requested as `ideal` constraints, so the browser may
  adjust them. Frames come from `MediaStreamTrackProcessor`, with a canvas fallback.

On Android, iOS and desktop, create the `CameraController` with the plugin's
default `imageFormatGroup`, or `ImageFormatGroup.yuv420` or
`ImageFormatGroup.bgra8888`. Another group, such as `ImageFormatGroup.nv21`,
stops the frame stream with an `UnsupportedError` on the first frame.

The plugins' own documentation is the primary source for permission details:
[`camera`](https://pub.dev/packages/camera) and
[`camera_desktop`](https://pub.dev/packages/camera_desktop).

## Quick start

This complete `lib/main.dart` initializes `yuv_ffi`, shows the camera through an orchestrator, and captures the visible frame.

```dart
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
  final _orchestrator = YuvCameraOrchestrator();
  final _viewController = YuvCameraViewController();
  YuvImage? _captured;

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
    _orchestrator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          YuvCameraLeaseBuilder(
            orchestrator: _orchestrator,
            builder: (context, controller) => YuvCameraView(cameraController: controller, viewController: _viewController),
          ),
          if (_captured case final image?)
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(width: 120, height: 160, child: YuvImageWidget(image: image)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _capture, child: const Icon(Icons.camera)),
    );
  }
}
```

What the example does:

- `YuvCameraLeaseBuilder` takes the camera from the orchestrator and passes its initialized `CameraController` to
  `builder`. The camera opens when the widget appears, and the widget releases it when removed or the app is hidden.
  It acquires a lease again when the app is shown. The camera closes once no lease is left (after `closeDelay`,
  zero by default).
- When there is no camera or permission is denied, the builder shows `Camera unavailable: …` with a `Retry` button.
  `placeholderBuilder(context, error, retry)` can replace this content; `error` is null while opening, and `retry`
  starts a new attempt without remounting. Calls during opening or while leased or hidden do nothing.
- `capture()` returns the next frame that is actually drawn, cropped to what is
  visible, or `null` if the view is not attached or stops first.
- You can still use your own `CameraController` with `YuvCameraView`; see [Main actions](#main-actions).

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

### Sharing one camera between screens

Several screens can show the same camera through one `YuvCameraOrchestrator`. A screen calls `acquire()` for a
`YuvCameraLease` and calls `release()` on it when it stops showing the camera; `YuvCameraLeaseBuilder` does both
while mounted and visible. Its `builder` can return `YuvCameraView`, `YuvTransformView` or a custom widget. The first
lease opens the camera, and releasing the last one closes it after `closeDelay` (zero by default). A lease taken
within that delay keeps the same controller. At most one controller is alive at any time: a
request made while the camera is closing waits until the old controller is disposed.

The builder releases its lease when the app is hidden and reacquires it when shown; `inactive` does not release it,
so camera permission prompts on Android do not interrupt opening. The orchestrator does not observe the app
lifecycle: the app must release manually acquired leases when it goes to the background.

The orchestrator works with an ordinary `ListenableBuilder` anywhere in the widget tree. Notifications arrive in a
microtask, and one notification can cover several state or error transitions in the same turn. The getters change
immediately; listeners read their current values. No notifications arrive after `dispose()`.

### Cutting a shape out of a frame

`croppedToShape` cuts the rectangle that a `YuvCropTarget` places in a `YuvImage` and keeps the `YuvCropShape` you
choose inside it. The source image is left unchanged. Call it after `YuvFfi.initialize()` has completed.

Targets: `YuvCropTarget.pixels(size)` is a box of exact pixels, `YuvCropTarget.fraction(left:, top:, right:, bottom:)`
takes its edges as fractions of the image, and `YuvCropTarget.square(side)` is a square whose side is a fraction of the
smaller image side. `pixels` and `square` also take `alignment` and `offset`.

The example's Shape crop screen offers these four combinations:

| Option | Target | Shape |
| --- | --- | --- |
| Rectangle (free width and height) | `YuvCropTarget.pixels(size)` | `YuvCropShape.rectangle` |
| Square (equal sides) | `YuvCropTarget.square(side)` | `YuvCropShape.rectangle` |
| Oval (vertical, face-shaped) | `YuvCropTarget.pixels(size)`, taller than wide | `YuvCropShape.ellipse` |
| Circle (equal axes) | `YuvCropTarget.square(side)` | `YuvCropShape.ellipse` |

Points outside the shape are painted with `fill` (black by default) in the result's `image`, and `toBgraBytes()` makes
them transparent. Transparency follows the shape, not a key color.

```dart
final image = await viewController.capture();
if (image != null) {
  final cut = image.croppedToShape(const YuvCropTarget.square(0.5), shape: YuvCropShape.ellipse);
  final bgra = cut.toBgraBytes(); // width * height * 4 bytes; alpha is 0 outside the circle
}
```

## Platforms and limits

Backend availability, building, and a confirmed physical camera are different
things. The checks run directly on the maintainer's machines with the scripts
in `tool/ci/` (the repository has no hosted CI), and their results are recorded
against exact commits. From the package root: `pwsh -File tool/ci/vm.ps1`,
`windows.ps1`, `android.ps1`, `web.ps1`, and `example.ps1` on Windows;
`bash tool/ci/linux.sh` on Linux; `bash tool/ci/macos.sh` and
`bash tool/ci/ios.sh` on macOS. So far they have confirmed:

- 108 example tests (`flutter test` in `example/`, run by `tool/ci/vm.ps1`, which builds `yuv_ffi.dll` from the resolved `yuv_ffi`): 86 camera, 7 device-check, 5 example navigation,
  4 toInputImage, 3 shape-crop screen, 2 orchestrator screen, 1 face screen.
- The native capture integration target on Windows (Release) and on a physical Pixel 3 (Android 12, `arm64-v8a`, debug build with the fake camera platform).
- The shape-crop and orchestrator-cycles integration targets on Windows, in Chrome (JavaScript, with a fake media
  stream), and on a physical Pixel 3 (Android 12, `arm64-v8a`).
- The Web camera source smoke and device-choice target in Chrome (JavaScript), including two distinct fake video inputs.
- The iOS observation in the `YuvCameraFrame` documentation: one iPhone,
  iOS 18.7, front camera, portrait and landscape.

A build or a passing emulator or fake-stream target does not prove that a
physical camera works on that platform. Other platforms, browsers (including
Safari and Firefox), `--wasm` builds, and devices are not claimed.

## Learn more

- [Wiki](https://github.com/Anfet/yuv_camera/wiki): step-by-step guides for
  preview, capture, frame processing, geometry, and platform troubleshooting.
- [Example app](example/README.md): a home screen with shape crop, open-and-close,
  ML Kit face-detection, and device-check screens.
- [API reference](https://pub.dev/documentation/yuv_camera/latest/) for every
  public class and parameter.
- [CHANGELOG.md](CHANGELOG.md).
- [`yuv_ffi`](https://github.com/Anfet/yuv_ffi) for images, operations, and
  geometry.

## Local development with an unpublished `yuv_ffi`

To develop this package against a local `yuv_ffi` checkout, resolve it through ignored local overrides. Create
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
