# yuv_camera example

This example opens a live camera preview, captures a frame through `YuvCameraView`, and displays it with `YuvFrameView`.
The capture result screen can pass the captured frame to Google ML Kit face detection. The Device check screen runs
the release validation flow recorded with the `DEVICE-1` report.

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

The native camera capture integration target passed on Windows Release and Android Tablet (x86_64/API 35). The Web
camera source smoke passed in Chrome JavaScript. A passing target does not prove a physical camera works; physical camera and
device-check claims remain limited to their separately recorded manual checks.
