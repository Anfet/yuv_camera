## 0.0.1

* First release of `yuv_camera`, extracted from the `yuv_ffi` example camera layer.
* Public API: `YuvCameraView`, `YuvCameraViewController`, `YuvCameraFrame`, `YuvCameraFrameSource` and
  `YuvTransformView`. Requires `yuv_ffi: ^0.5.2`; works with `camera` 0.11 and 0.12 (`>=0.11.0+2 <0.13.0`).
* Native frame sources accept the `yuv420` and `bgra8888` image format groups (the plugin defaults); another group stops
  the stream with an `UnsupportedError`.
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
* Android, iOS, desktop (through `camera_desktop` registered by the application) and Web frame sources over the
  `camera` plugin; ML Kit is not a dependency and is connected through `onFrame`.
* Frame orientation: on Android frames are rotated by the sensor and device orientation and the front camera is mirrored;
  on Windows and Web frames are not rotated and every camera except a back one is mirrored, as the `camera_desktop` and
  `camera_web` previews are; iOS, macOS and Linux frames are upright and not mirrored.
* Example application built on one `YuvCameraOrchestrator`: a home screen with Shape crop, Open & close, ML Kit face-detection
  and device-check screens.
* The package has no GitHub Actions workflows: its checks are the scripts in `tool/ci/`, run directly on the
  maintainer's machines.
* Verified locally: 108 example tests, native capture on Windows (Release) and a physical Pixel 3 (Android 12, `arm64-v8a`), the
  shape-crop and orchestrator-cycles targets on Windows, in Chrome (JavaScript, fake device) and on Pixel 3, Web camera
  source smoke and device-choice target with two distinct fake video inputs in Chrome (JavaScript).
  Physical-camera behavior is not claimed beyond the documented iOS observation.
* README with package selection, platform setup (permissions, `camera_desktop` on desktop), a complete Quick start,
  ownership rules for frames and captures, and the verified-platform limits. `capture()` may return `null`; Safari,
  Firefox, `--wasm` builds and other devices are not claimed.
* Step-by-step guides in the [GitHub Wiki](https://github.com/Anfet/yuv_camera/wiki).
* Migration from the `yuv_ffi` 0.5.1 example: depend on `yuv_camera` instead of copying its camera code, and register
  `camera_desktop` in the application on desktop.
