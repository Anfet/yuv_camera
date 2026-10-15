# yuv_camera example

The home screen offers four scenarios. Every screen takes the camera from one `YuvCameraOrchestrator`, does one thing,
and gives it back when you leave:

- Shape crop: capture a frame, pick a shape, place it, and see exactly which pixels were cut out.
- Open & close: open, close and reopen the camera fast through the orchestrator. Nothing should fail.
- Face detection: live ML Kit face box over the preview, with a plain Face detected or No face label.
- Device check: the guided, step-by-step check of preview, capture and frame rate on this device.

The minimal usage is the Quick start in the [package README](../README.md); this app is the larger scenario with
shape crop, ML Kit, and device checks.

Step-by-step guides are in the [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki).

## Run

From this directory, run `flutter pub get` and then `flutter run -d <device>` on a supported device. The example uses
`yuv_camera` from `..` and `yuv_ffi: ^0.5.2`. To run it against a local `yuv_ffi` checkout instead, add an ignored
`pubspec_overrides.yaml` in this directory (see the package README, "Local development"), or run
`tool/check_pair.ps1` from the repository root, which does it for an exact pair of checkouts.

On desktop, the example uses the `camera_desktop` federated implementation; the application, not `yuv_camera`,
declares it. Linux builds require GStreamer development libraries; macOS needs `NSCameraUsageDescription` and the
camera entitlement (both set here). Web camera access requires Chrome over localhost or HTTPS and browser permission.
ML Kit face detection runs only on Android and iOS; other platforms skip it. For Android release builds, R8 removes the constructors ML Kit needs to start, so the example keeps them in android/app/proguard-rules.pro; an app using ML Kit needs the same rule.

## Verified

The checks are run from the repository root with the scripts in `tool/ci/` (see "Platforms and limits" in the package
README); there is no hosted CI. Each result names its mode and device; exact test totals belong to each gate run.

- `tool/ci/vm.ps1`: the example VM suite for camera lifecycle, device-check, navigation, image conversion, shape crop,
  orchestrator and face-screen behavior.
- `tool/ci/windows.ps1` (release build): the native capture target with the fake camera platform, and the shape-crop and
  orchestrator-cycles targets with the Windows 10 built-in webcam.
- `tool/ci/android.ps1` on a physical Pixel 3 (Android 12, `arm64-v8a`, debug build): the native capture target with the
  fake camera platform, and the orchestrator-cycles and shape-crop targets.
- `tool/ci/linux.sh` on Ubuntu 24.04 in a VirtualBox VM: the native capture target with the fake camera platform; the
  shape-crop and orchestrator-cycles targets with the webcam passed through to the guest (not attached directly).
- macOS 15.6 (arm64), native capture target with the fake camera platform (no physical camera): `tool/ci/macos.sh`
  in the Mac GUI run runs `camera_capture_native_test.dart`, which uses the fake platform.
- macOS 15.6 (arm64) built-in camera: the Mac GUI run's shape crop and orchestrator cycles, with two previews, the
  second continuing after the first is removed, and final close.
- `tool/ci/ios.sh` on the iOS 18.6 simulator: capture, shape-crop and BGRA fixture targets, no camera.
- Chrome (JavaScript build) on Windows with a physical webcam: the Web camera source smoke, shape-crop and
  orchestrator-cycles targets, run through `tool/ci/drive.ps1` with the `web-server` target and no fake device.
- Chrome (JavaScript build) on a fake media stream: the device-choice target with two distinct fake video inputs, the
  only fake-stream result (`tool/ci/web.ps1`).
- An iPhone 11 on iOS 18.7.8: the orchestrator, camera-flow and BGRA integration targets, and a signed Release device
  check (portrait idle and heavy load, landscape, face portrait and landscape, mirror, capture).
- The `YuvCameraFrame` iOS 18.7 observation (one iPhone, front camera, portrait and landscape) stays as documented.

A passing target does not prove that a physical camera works. Physical-camera claims are limited to the devices and modes
named above; other platforms, browsers (including Safari and Firefox), `--wasm` builds, other devices and OS versions are
not claimed.
