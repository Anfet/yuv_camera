# yuv_camera

Flutter camera package built on yuv_ffi for capturing and displaying YUV camera frames.

`yuv_camera` shows a live camera preview through the `yuv_ffi` frame presenter, hands each camera frame to your code
as a `YuvImage`, and captures the frame that is actually on screen. It is a Dart/Flutter package over the existing
`camera` plugin: it has no native plugin, platform channel or FFI layer of its own, and `yuv_ffi` never depends on it.

## Public API

Everything is exported from `package:yuv_camera/yuv_camera.dart`.

| Type | Purpose |
| --- | --- |
| `YuvCameraView` | Preview widget for an initialized `CameraController`. Optional `onFrame` (throttled by `onFrameInterval`, default 200 ms), `overlayBuilder`, `fit`, `alignment`, `onFramePresented`, `onStreamStopped`. |
| `YuvCameraViewController` | Optional handle for a `YuvCameraView`: `capture()` returns the next frame that is actually drawn, cropped to what is visible; `geometry` exposes the current `YuvFrameGeometry`. |
| `YuvCameraFrame` | One immutable camera delivery: `width`, `height`, `format`, `orientation`, `timestamp`, `image` (raw, imported on first access) and `upright()` (packed and oriented, cached). |
| `YuvCameraFrameSource` | Low-level frame stream over a `CameraController` (`start`, `stop`, `dispose`); it delivers every frame and leaves throttling to the consumer. |
| `YuvTransformView` | Preview that synchronously transforms each accepted frame with `transform` before it is drawn. |

Frames and captured images are owned by the package and must not be mutated; call `copy()` before an in-place
operation. Heavy synchronous work in `onFrame` blocks the UI isolate.

## Install

```yaml
dependencies:
  yuv_camera: ^0.0.1
  camera: ^0.11.0+2
```

`yuv_camera` depends on `yuv_ffi: ^0.5.2`, so the pair is resolved by pub. Call `await YuvFfi.initialize();` from
`yuv_ffi` before the first frame, as the example does. Requirements: Dart `^3.12.0`, Flutter `>=3.44.0`.

## Platforms and permissions

- **Android, iOS:** the `camera` plugin requests the camera permission; iOS needs `NSCameraUsageDescription` in
  `Info.plist`.
- **Windows, macOS, Linux:** add `camera_desktop: ^2.0.0` next to `camera` in the application. `yuv_camera` does not
  depend on it or register it. macOS needs `NSCameraUsageDescription` and the `com.apple.security.device.camera`
  entitlement; Linux builds need the GStreamer development libraries
  (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`).
- **Web:** Chrome over localhost or HTTPS with browser camera permission; frames come from `MediaStreamTrackProcessor`,
  with a canvas fallback.

## Processing frames with ML Kit

ML Kit is not a dependency of this package. Pass an `onFrame` handler and convert the frame in your application; the
example (`example/lib/ext.dart`, `toInputImage`) packs a `YuvImage` into an `InputImage` for
`google_mlkit_face_detection` and applies the frame's `orientation.rotation`.

## What is verified

The package checks run directly on the maintainer's machines with the scripts in `tool/ci/` (the repository has no
hosted CI), and their results are recorded against exact commits. From the package root: `pwsh -File tool/ci/vm.ps1`,
`windows.ps1`, `android.ps1`, `web.ps1` and `example.ps1` on Windows; `bash tool/ci/linux.sh` on Linux;
`bash tool/ci/macos.sh` and `bash tool/ci/ios.sh` on macOS. So far they have confirmed:

- 34 example tests (26 camera, 5 device-check, 3 `toInputImage`).
- The native capture integration target on Windows (Release) and on the Android `Tablet` emulator
  (x86_64, API 35).
- The Web camera source smoke in Chrome (JavaScript) with a fake media stream.
- The iOS observation in the `YuvCameraFrame` documentation: one iPhone, iOS 18.7, front camera, portrait and
  landscape.

A build or a passing emulator or fake-stream target does not prove a physical camera works on that platform. Other
platforms, browsers and devices are not claimed.

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
