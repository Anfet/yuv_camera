## 0.0.1

* First release of `yuv_camera`, extracted from the `yuv_ffi` example camera layer.
* Public API: `YuvCameraView`, `YuvCameraViewController`, `YuvCameraFrame`, `YuvCameraFrameSource` and
  `YuvTransformView`. Requires `yuv_ffi: ^0.5.2`.
* Android, iOS, desktop (through `camera_desktop` registered by the application) and Web frame sources over the
  `camera` plugin; ML Kit is not a dependency and is connected through `onFrame`.
* Example application with capture, an ML Kit face-detection screen and a device-check screen.
* The package has no GitHub Actions workflows: its checks are the scripts in `tool/ci/`, run directly on the
  maintainer's machines.
* Verified locally: 34 example tests, native capture on Windows (Release) and the Android `Tablet` emulator, Web camera
  source smoke in Chrome (JavaScript). Physical-camera behavior is not claimed beyond the documented iOS observation.
