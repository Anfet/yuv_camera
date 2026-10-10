# yuv_camera example

This example opens a live camera preview, captures a frame through `YuvCameraView`, and displays it with `YuvFrameView`.
The capture result screen can pass the captured frame to Google ML Kit face detection. The Device check screen runs
the release validation flow recorded with the `DEVICE-1` report.

## Run

From this directory, run `flutter pub get` and then `flutter run -d <device>` on a supported device. On desktop, the
example uses the `camera_desktop` federated implementation; Linux builds require GStreamer development libraries.
Web camera access requires Chrome over localhost or HTTPS and browser permission.

The native camera capture integration target passed on Windows Release and Android Tablet (x86_64/API 35). The Web
camera source smoke passed in Chrome JavaScript. Physical camera and device-check claims remain limited to their
separately recorded manual checks.
