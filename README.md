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
  yuv_camera: ^0.1.0
  yuv_ffi: ^0.5.2
  camera: ^0.12.1
  # Windows, macOS, and Linux only:
  camera_desktop: ^2.0.0
```

Requirements: Dart `^3.12.0`, Flutter `>=3.44.0`; officially tested and supported with Flutter 3.44.9.
`yuv_camera` requires
`yuv_ffi: ^0.5.2` and declares compatibility with `camera` versions
`>=0.12.1 <0.13.0`. Physical Android preview is verified with `camera`
0.12.1. The earlier `camera` 0.11.0+2 / CameraX 0.6.30 combination produced
inconsistent physical preview results and is outside this dependency range; see
the [platform verification table](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting#what-is-verified).

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
stops the frame stream with an `UnsupportedError` on the first frame. Native
`yuv420` frames with two planes are imported as NV12 (`Y`, interleaved `UV`);
three planes are imported as I420 (`Y`, `U`, `V`). One-plane BGRA remains
packed. Plane row strides and layouts are preserved, and malformed layouts
stop the stream through `onError`. YUV conversion uses BT.601 limited/video
range as defined by `yuv_ffi`. The package does not detect full-range data or
select another color matrix, and BGRA has no YUV range conversion.

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
              child: SizedBox(width: 120, height: 160, child: YuvImageWidget(image: image, boxFit: BoxFit.contain)),
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
  visible, or `null` if the view is not attached or stops before drawing. A
  stream ending unexpectedly is reported as a stream error and stops the view.
  There is no built-in capture timeout; if an attached view has not drawn a
  frame, the future stays pending until it draws or the view is removed.
- `viewController.geometry` is `null` before the first frame, while the view is
  detached, and while it switches to another controller. Read it again after
  the notifier changes.
- A `YuvCameraOrchestrator` treats a controller error or frame-stream failure as terminal: active leases are invalidated,
  the controller is drained and disposed, and `YuvCameraLeaseBuilder` shows Retry. Retry opens a fresh controller.
- A native controller's image stream is exclusively owned while a YUV source is active. Do not call
  `startImageStream`, `startVideoRecording(onAvailable: ...)`, or subscribe directly to platform frames on that controller.
  An already active image stream is rejected; later external starts cannot be intercepted reliably.
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
synchronous work in `onFrame` blocks the UI isolate and stops painting. On
Android, frame orientation follows the current device and sensor orientation;
`CameraController.lockCaptureOrientation()` does not lock the orientation
reported for YUV preview frames. To switch cameras, remove the view and create
a new controller for the selected camera; changing its description in place
stops the active YUV source rather than switching it seamlessly.

### Processing frames with ML Kit

ML Kit is not a dependency of this package. Pass an `onFrame` handler and
convert the frame in your application; the example (`example/lib/ext.dart`,
`toInputImage`) packs a `YuvImage` into an `InputImage` for
`google_mlkit_face_detection` and applies the frame's `orientation.rotation`.

### Sharing one camera between screens

Several screens can show the same camera through one `YuvCameraOrchestrator`, for example by placing two
`YuvCameraLeaseBuilder` widgets in the tree. Each builder holds an independent lease and can build a `YuvCameraView`,
`YuvTransformView` or custom widget. The first lease opens one shared controller; releasing one lease leaves the
other preview running. Releasing the last lease closes the camera after `closeDelay` (zero by default). A lease taken
within that delay keeps the same controller. At most one controller is alive at any time: a request made while the
camera is closing waits until the old controller is disposed.

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
in `tool/ci/` of the Git repository (the pub.dev archive does not include
`tool/`; the repository has no hosted CI), and their results are recorded
against exact commits. From the package root of a Git checkout:
`pwsh -File tool/ci/vm.ps1`,
`windows.ps1`, `android.ps1`, `web.ps1`, and `example.ps1` on Windows;
`bash tool/ci/linux.sh` on Linux; `bash tool/ci/macos.sh` and
`bash tool/ci/ios.sh` on macOS. So far they have confirmed:

- The example VM suite (`flutter test` in `example/`, run by `tool/ci/vm.ps1`, which builds `yuv_ffi.dll` from the
  resolved `yuv_ffi`), covering camera lifecycle, device-check, navigation, image conversion, shape crop, orchestrator
  and face screen behavior. Exact test totals are recorded with each gate run.
- The native capture integration target with the fake camera platform (no physical camera): on Windows (Release), on a
  physical Pixel 3 (Android 12, `arm64-v8a`, debug and Release builds), on Linux (Ubuntu 24.04 in a VirtualBox VM), on
  macOS 15.6 (arm64) and on the iOS 18.6 simulator.
- The orchestrator-cycles integration target with a physical camera:
  - the built-in webcam on Windows 10 (Release);
  - Chrome (JavaScript build) on Windows with a physical webcam, camera permission auto-approved and no fake device;
  - a physical Pixel 3 (Android 12, `arm64-v8a`, Release build);
  - a webcam passed through to an Ubuntu 24.04 VirtualBox guest (not a camera attached directly to the Linux machine);
  - the built-in camera on macOS 15.6 (arm64), where the orchestrator cycles also confirmed two previews, the second
    continuing after the first is removed, and the final close.
- The shape-crop integration target, which needs no camera and runs on the real YUV backend of the platform, on the same
  platforms, devices and modes as the orchestrator-cycles target above.
- The Web camera source smoke target in Chrome (JavaScript build) with a physical webcam on Windows.
- The Web device-choice target in Chrome (JavaScript build) on a fake media stream with two distinct fake video inputs.
  It is the only fake-stream result and claims no physical camera.
- The iOS 18.6 simulator fixture targets (capture, shape crop and BGRA) without a camera. The two-plane NV12 fixture target models plugin bytes only. On an iPhone 11 (iOS 18.7.8) the physical NV12 integration target passed for the front and back cameras: raw frames, drawn preview and capture. Portrait, landscape and mirror modes were not exercised separately for NV12.
- An iPhone 11 on iOS 18.7.8: the orchestrator, camera-flow and BGRA integration targets, and a signed Release device
  check (portrait idle and heavy load, landscape, face portrait and landscape, mirror, capture). The operator also
  confirmed two previews with the second continuing after the first is removed, and landscape capture in Shape crop.
- The iOS observation in the `YuvCameraFrame` documentation: one iPhone,
  iOS 18.7, front camera, portrait and landscape.

A build or a passing emulator or fake-stream target does not prove that a
physical camera works on that platform. Physical-camera claims remain limited to the named devices, modes and scenarios.

Additional physical preview/capture and stop/dispose consumer scenarios passed with Flutter 3.44.9:

| Browser / device | Checked build and scope |
| --- | --- |
| Firefox 143 on Windows | JavaScript, external webcam. |
| Safari 18.6 on macOS 15.6.1 | JavaScript, External-camera fixture only; no front/back lens claim. |
| Chrome on a Pixel 3 | JavaScript over HTTPS; the scenario passed, but the operator observed low speed and no speed threshold was defined. |
| Safari on an iPhone 11 | JavaScript over HTTPS. |

These are bounded consumer observations, not a complete browser conformance or image-operation parity matrix.
Camera `--wasm`, Safari/Firefox WASM and other browser/device configurations remain outside the support claims.

The standard Chrome scenarios use the default Flutter asset layout. General public `assetBase`/CDN/CSP support is not
established by internal-loader experiments. Static CocoaPods camera runtime remains unverified; the FFI-only static
Firebase consumer in the `yuv_ffi` README does not establish camera capture support.

## Known observation: Chrome VideoFrame warning

Chrome 155 on Windows with Flutter 3.44.9, JavaScript/CanvasKit, can report a `VideoFrame` collected without an explicit
close during camera teardown/reopening. Physical start/capture/stop/reopen scenarios passed, and the observed camera
frames were closed. The cause and owner remain unknown; this does not prove the absence of a package defect or a leak,
and no fix is claimed. The observation is retained for this release.

The [investigation and preserved evidence](https://github.com/Anfet/yuv_camera/blob/main/doc/evidence/M2/README.md)
record eight diagnostic/control runs and their limits. Revisit it for a reproducible stall/capture failure, confirmed
resource accumulation or a proven missed-close path; recurrence of the warning alone does not establish one.

## Learn more

- [Wiki](https://github.com/Anfet/yuv_camera/wiki): step-by-step guides for
  preview, capture, frame processing, geometry, and platform troubleshooting.
- [Example app](example/README.md): a home screen with shape crop, open-and-close,
  ML Kit face-detection, and device-check screens.
- [API reference](https://pub.dev/documentation/yuv_camera/latest/) for every
  public class and parameter.
- [CHANGELOG.md](CHANGELOG.md).
- [MIGRATION.md](MIGRATION.md) for applications that copied camera code from the `yuv_ffi` example.
- [`yuv_ffi`](https://github.com/Anfet/yuv_ffi) for images, operations, and
  geometry.

## Local development with an unpublished `yuv_ffi`

Local development needs a Git checkout of this repository: the pub.dev archive does not include `tool/`, so the
`tool/` scripts below are not available from a downloaded package. To develop this package against a local `yuv_ffi`
checkout, resolve it through ignored local overrides. Create
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

## Verification boundaries

The package allows Flutter 3.44.0 or later. Flutter 3.44.9 is the officially tested and supported version.
Earlier Flutter 3.44.x patch releases may work, but have not been verified.

Web evidence includes Chrome JavaScript and the limited Firefox/Safari/mobile JavaScript consumer scenarios listed
above. It does not establish support for every browser or device. General public custom asset placement/CDN/strict-CSP
support and static CocoaPods camera runtime remain unverified. Camera `--wasm` is not claimed.
A desktop camera provider does not prove physical capture support. Physical iPhone NV12 front/back preview and capture evidence does not establish
separate NV12 landscape or mirror support.
