# yuv_camera example

This example opens a live camera preview, captures a frame through `YuvCameraView`, and displays it with `YuvFrameView`.
The capture result screen can pass the captured frame to Google ML Kit face detection. The Device check screen runs
the release validation flow recorded with the `DEVICE-1` report.

The minimal usage is the Quick start in the [package README](../README.md); this app is the larger scenario with
capture, ML Kit, and device checks.

## Run

From this directory, run `flutter pub get` and then `flutter run -d <device>` on a supported device. The example uses
`yuv_camera` from `..` and `yuv_ffi: ^0.5.2`. Until that `yuv_ffi` is published, resolve it through an ignored
`pubspec_overrides.yaml` in this directory (see the package README, "Local development"), or run
`tool/check_pair.ps1` from the repository root, which does it for an exact pair of checkouts.

On desktop, the example uses the `camera_desktop` federated implementation; the application, not `yuv_camera`,
declares it. Linux builds require GStreamer development libraries; macOS needs `NSCameraUsageDescription` and the
camera entitlement (both set here). Web camera access requires Chrome over localhost or HTTPS and browser permission.
ML Kit face detection runs only on Android and iOS; other platforms skip it.

## Verified

The checks are run from the repository root with the scripts in `tool/ci/` (see "Platforms and limits" in the package
README); there is no hosted CI. The native camera capture integration target passed on Windows Release and on a physical Pixel 3 (Android 12, `arm64-v8a`). The Web
camera source smoke passed in Chrome JavaScript. A passing target does not prove a physical camera works; physical camera and
device-check claims remain limited to their separately recorded manual checks.
