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
`pubspec_overrides.yaml` in this directory (see the package README, "Local development"), or, from a Git checkout, run
`tool/check_pair.ps1` from the repository root, which does it for an exact pair of checkouts. The pub.dev archive does
not include `tool/`.

On desktop, the example uses the `camera_desktop` federated implementation; the application, not `yuv_camera`,
declares it. Linux builds require GStreamer development libraries; macOS needs `NSCameraUsageDescription` and the
camera entitlement (both set here). Web camera access requires Chrome over localhost or HTTPS and browser permission.
ML Kit face detection runs only on Android and iOS; other platforms skip it. For Android release builds, R8 removes the constructors ML Kit needs to start, so the example keeps them in android/app/proguard-rules.pro; an app using ML Kit needs the same rule.

To run with the Flutter Driver Extension enabled for Dart MCP widget diagnostics, use the dedicated debug entrypoint from this directory:

```sh
flutter run -d <device-id> --target=test_driver/app.dart
```

The example checkout does not include a Linux runner. To try the local pair on Linux, archive the committed package
trees into a temporary directory and generate the runner there. Keep the example under its package: its `path: ..`
dependency needs that parent directory. From the `yuv_camera` Git checkout, with `yuv_ffi` in the sibling directory:

```bash
set -euo pipefail
linux_copy=$(mktemp -d)
mkdir "$linux_copy/yuv_camera" "$linux_copy/yuv_ffi"
git -c core.autocrlf=false archive HEAD | tar -x -C "$linux_copy/yuv_camera"
git -C ../yuv_ffi -c core.autocrlf=false archive HEAD | tar -x -C "$linux_copy/yuv_ffi"
cd "$linux_copy/yuv_camera/example"
cat > pubspec_overrides.yaml <<'YAML'
dependency_overrides:
  yuv_ffi:
    path: ../../yuv_ffi
YAML
flutter create --platforms=linux --project-name yuv_camera_example .
flutter pub get
flutter run -d linux
```

This leaves both source checkouts unchanged. The temporary pair uses each checkout's committed `HEAD`; uncommitted
changes and ignored overrides are excluded. The Linux prerequisites above still apply.

## Verified

The checks are run from the root of the Git repository with the scripts in `tool/ci/` (not included in the pub.dev
archive; see "Platforms and limits" in the package README); there is no hosted CI. Each result names its mode and device; exact test totals belong to each gate run.

- `tool/ci/vm.ps1`: the example VM suite for camera lifecycle, device-check, navigation, image conversion, shape crop,
  orchestrator and face-screen behavior.
- `tool/ci/windows.ps1` (release build): the native capture target with the fake camera platform, the orchestrator-cycles
  target with the Windows 10 built-in webcam, and the shape-crop target, which needs no camera.
- `tool/ci/android.ps1` on a physical Pixel 3 (Android 12, `arm64-v8a`): the native capture target with the
  fake camera platform (debug and Release builds), and the orchestrator-cycles and shape-crop targets (Release build; the
  shape-crop target needs no camera).
- `tool/ci/linux.sh` on Ubuntu 24.04 in a VirtualBox VM: the native capture target with the fake camera platform; the
  orchestrator-cycles target with the webcam passed through to the guest (not attached directly), and the shape-crop
  target, which needs no camera.
- macOS 15.6 (arm64), native capture target with the fake camera platform (no physical camera): `tool/ci/macos.sh`
  in the Mac GUI run runs `camera_capture_native_test.dart`, which uses the fake platform.
- macOS 15.6 (arm64) built-in camera: the Mac GUI run's orchestrator cycles, with two previews, the
  second continuing after the first is removed, and final close; its shape-crop target needs no camera.
- `tool/ci/ios.sh` on the iOS 18.6 simulator: capture, shape-crop and BGRA fixture targets, no camera.
- Chrome (JavaScript build) on Windows with a physical webcam: the Web camera source smoke and orchestrator-cycles
  targets, run through `tool/ci/drive.ps1` with the `web-server` target and no fake device; the shape-crop target runs
  there without a camera.
- Chrome (JavaScript build) on a fake media stream: the device-choice target with two distinct fake video inputs, the
  only fake-stream result (`tool/ci/web.ps1`).
- An iPhone 11 on iOS 18.7.8: the orchestrator, camera-flow and BGRA integration targets, and a signed Release device
  check (portrait idle and heavy load, landscape, face portrait and landscape, mirror, capture).
- The `YuvCameraFrame` iOS 18.7 observation (one iPhone, front camera, portrait and landscape) stays as documented.

A passing target does not prove that a physical camera works. Additional JavaScript consumer preview/capture and
stop/dispose scenarios passed on Firefox 143 / Windows (external webcam), Safari 18.6 / macOS 15.6.1 (External fixture),
Pixel 3 Chrome over HTTPS and iPhone 11 Safari over HTTPS. These bounded observations are not complete browser or
image-operation parity. Camera `--wasm` and other configurations remain outside the support claims. See the
[verification bounds and known Chrome warning](../README.md#platforms-and-limits).
