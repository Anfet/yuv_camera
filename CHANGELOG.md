## 0.0.1

* Web frame sources cancel each reader once, handle cancellation rejection, and drain pending teardown across restarts.
* First release of `yuv_camera`, extracted from the `yuv_ffi` example camera layer.
* Camera capture waits for a painted preview frame and stays pending while the view is offstage.
* Capture has no built-in timeout; removing the view ends a pending capture with `null`. A controller id or description
  change stops its active YUV source, so camera switching uses a newly initialized controller and view update.
* The orchestrator handles platform `CameraErrorEvent`s and cancels its subscription before disposing the controller.
* Terminal controller or frame-stream errors invalidate orchestrator leases and drain frame cancellation before
  disposal; `YuvCameraLeaseBuilder` can retry with a fresh controller without route navigation.
* Native YUV frame sources document exclusive image-stream ownership and reject controllers with an already active
  image stream.
* Camera frame delivery uses one shared native stream per controller while each consumer can stop independently;
  unexpected stream EOF is reported as an error and terminates active deliveries.
* Capture returns the frame actually drawn with the view geometry applied. Frame deliveries and their cached images are
  immutable by contract; copy an image before an in-place operation. Sharing guidance demonstrates concurrent previews
  and explains that releasing one lease leaves other consumers running.
* Public API: `YuvCameraView`, `YuvCameraViewController`, `YuvCameraFrame`, `YuvCameraFrameSource` and
  `YuvTransformView`. Requires `yuv_ffi: ^0.5.2`; works with `camera` 0.12 (`>=0.12.1 <0.13.0`);
  `camera` 0.11.0+2 is not supported because it produced inconsistent physical Android preview results.
* Native frame sources accept the `yuv420` and `bgra8888` image format groups (the plugin defaults); another group stops
  the stream with an `UnsupportedError`.
* Native two-plane `yuv420` frames are imported as NV12, three-plane frames as I420, and one-plane BGRA remains packed.
  Source strides are preserved; incompatible layouts stop the stream with a `FormatException`. YUV conversion uses
  BT.601 limited/video range; full-range data and other color matrices are not detected. The iOS NV12 fixture models plugin bytes only; physical NV12 capture (raw frames, drawn preview and capture, front and back cameras) was verified on an iPhone 11 with iOS 18.7.8, without separate portrait, landscape or mirror NV12 runs.
* Orchestrator: `YuvCameraOrchestrator` leases the single camera through `acquire()` and `YuvCameraLease.release()`,
  closes it after `closeDelay`, keeps at most one controller alive, and reports `YuvCameraState`;
  `YuvCameraLeaseBuilder` passes its initialized controller to a builder, retries after opening failures and releases
  its lease while the app is hidden. Orchestrator notifications are asynchronous and coalesced in a microtask.
* `onStreamStopped` on both views is called only after a stream error, never on removal or controller replacement.
  View controller binding methods are internal.
* Web frames come from a second media stream on the controller's device, matched by its unique, non-empty camera
  label; empty, missing or duplicate labels fall back to the camera direction. The controller's `ResolutionPreset`
  and optional `fps` are requested as `ideal` constraints and may be adjusted by the browser.
  Scaled or opaque browser frames are rendered through canvas at their display dimensions before pixel import.
* Shape crop: `YuvCropTarget` (`pixels`, `fraction`, `square`), `YuvCropShape` (`rectangle`, `ellipse`), `YuvShapedImage`
  and `YuvImage.croppedToShape`; points outside the shape are painted with a fill color and are transparent in
  `toBgraBytes()`.
* Android, iOS, desktop (through the application's `camera_desktop` dependency, registered by Flutter) and Web frame sources over the
  `camera` plugin; ML Kit is not a dependency and is connected through `onFrame`.
* Frame orientation: on Android frames are rotated by the sensor and device orientation and the front camera is mirrored;
  on Windows and Web frames are not rotated and every camera except a back one is mirrored, as the `camera_desktop` and
  `camera_web` previews are; iOS, macOS and Linux frames are upright and not mirrored.
* Example application built on one `YuvCameraOrchestrator`: a home screen with Shape crop, Open & close, ML Kit face-detection
  and device-check screens.
* The package has no GitHub Actions workflows: its checks are the scripts in `tool/ci/` of the Git repository (not
  included in the pub.dev archive), run directly on the maintainer's machines.
* Verified locally, with mode and device named per result: example VM suite (`tool/ci/vm.ps1`) for camera lifecycle,
  device-check, navigation, image conversion, shape crop, orchestrator and face-screen behavior; native capture target
  with the fake camera platform on Windows (Release), a physical Pixel 3 (Android 12, `arm64-v8a`, debug and Release), Linux
  (Ubuntu 24.04 VM), macOS 15.6 and the iOS 18.6 simulator; orchestrator-cycles target with a physical camera on
  Windows 10 (Release, built-in webcam), in Chrome (JavaScript build) on Windows with a physical webcam and no fake device,
  on a physical Pixel 3 (Release), on Ubuntu 24.04 with the webcam passed through VirtualBox (not attached directly), and on
  the macOS 15.6 built-in camera (two previews, the second continuing after the first is removed, final close);
  shape-crop target, which needs no camera, on the real backend of the same platforms, devices and modes; Web camera
  source smoke with a physical webcam in Chrome (JavaScript build) on Windows; Web device-choice target in Chrome
  (JavaScript build) on a fake media stream with two distinct fake video inputs, the only fake-stream result; iOS 18.6
  simulator fixture targets for capture, shape crop and BGRA without a camera; iPhone 11 on iOS 18.7.8 for the
  orchestrator, camera-flow and BGRA integration targets and a signed Release device check (portrait idle and heavy load,
  landscape, face portrait and landscape, mirror, capture); the `YuvCameraFrame` iOS 18.7 observation. Physical-camera
  results are limited to the devices and modes listed here; a build, a passing emulator or fake-stream target does not
  prove a physical camera works, and other platforms, browsers, `--wasm` builds, other devices and OS versions are not
  claimed.
* README with package selection, platform setup (permissions, `camera_desktop` on desktop), a complete Quick start,
  ownership rules for frames and captures, and the verified-platform limits. `capture()` may return `null`; Safari,
  Firefox, `--wasm` builds and other devices are not claimed.
* Step-by-step guides in the [GitHub Wiki](https://github.com/Anfet/yuv_camera/wiki).
* Migration from the `yuv_ffi` 0.5.1 example: depend on `yuv_camera` instead of copying its camera code, and add
  `camera_desktop` beside `camera` on desktop. Flutter registers the federated plugin when the app is rebuilt.
  See [MIGRATION.md](MIGRATION.md) for imports, controller ownership, frame formats and ML Kit.
