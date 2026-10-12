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
README); there is no hosted CI. The recorded runs of `tool/ci/vm.ps1` passed 108 example tests. The `tool/ci/windows.ps1` script (release build) passed the
native capture, shape-crop and orchestrator-cycles targets on Windows. The `tool/ci/web.ps1` script passed the Web camera
  source smoke, device-choice, shape-crop and orchestrator-cycles targets in Chrome JavaScript; device-choice uses two distinct fake video inputs. The
`tool/ci/android.ps1` script passed the native capture, orchestrator-cycles and shape-crop targets on a physical Pixel 3
(Android 12, `arm64-v8a`). A passing target does not prove a physical camera works; physical camera and device-check claims
remain limited to their separately recorded manual checks.
