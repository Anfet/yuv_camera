# Platforms and troubleshooting

**Task:** set up permissions and the camera provider for each platform, know exactly what has been verified, and fix the
failures you are most likely to meet.

**Conditions:** your app depends on `yuv_camera`, `yuv_ffi` and `camera` (see
[Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started)).

## Platform setup

| Platform | Setup |
| --- | --- |
| Android | `minSdk` 26 or higher, because `yuv_ffi` requires API 26. The `camera` plugin requests the camera permission at run time. |
| iOS | `NSCameraUsageDescription` with a short reason in `ios/Runner/Info.plist`. |
| macOS | `NSCameraUsageDescription` in `Info.plist`, and the `com.apple.security.device.camera` entitlement in each entitlements file you ship (typically the debug and release ones). |
| Windows | `camera_desktop` in your `pubspec.yaml`; nothing else. |
| Linux | `camera_desktop` in your `pubspec.yaml`, and the GStreamer development libraries (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`) installed before building. |
| Web | Chrome over `localhost` or HTTPS, and the browser's camera permission. |

The plugins' documentation is the primary source for permission details:
[`camera`](https://pub.dev/packages/camera) and [`camera_desktop`](https://pub.dev/packages/camera_desktop).

### Desktop: Windows, macOS, Linux

`camera` talks to the platform through a provider package. For Android, iOS and Web the default provider comes with
`camera`; on Windows, macOS and Linux your app adds `camera_desktop` next to `camera`, and it is picked up as a federated
plugin. `yuv_camera` does not depend on `camera_desktop` and does not register it: the choice of provider is the
application's.

The `camera` package restricts `CameraController.startImageStream` to Android and iOS. `yuv_camera` therefore reads frames
from the platform interface (`CameraPlatform.instance.onStreamedFrameAvailable`) directly, which is how desktop frames
reach `onFrame`, `YuvCameraFrameSource` and the preview. You do not call `startImageStream` yourself.

On Windows, frames from every camera except a back one are mirrored and not rotated, as in the `camera_desktop` preview,
which reports every Windows camera as front. On macOS and Linux the package applies no rotation and no mirror.

### Web

- `yuv_camera` opens a second media stream on the controller's device, matched by its unique, non-empty camera label.
  Empty, missing or duplicate labels fall back to the camera direction (`front` requests `user`, `back` and `external`
  request `environment`). The controller's `ResolutionPreset` and optional `fps` are requested as `ideal` constraints,
  so the browser may adjust them. Device enumeration or stream-opening failures stop the source and reach `onError`.

- Browsers expose the camera only in a secure context: serve the app from `localhost` or over HTTPS, and let the user
  grant the camera permission ([MDN: `getUserMedia`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)).
- Frames require `MediaStreamTrackProcessor` or `HTMLVideoElement.requestVideoFrameCallback`. Where the processor is
  unavailable, the source reads canvas frames scheduled by `requestVideoFrameCallback`. If neither path is available,
  the source stops all its tracks and reports `UnsupportedError: Camera frames require MediaStreamTrackProcessor or
  requestVideoFrameCallback` through `onError`. This prerequisite does not extend the verified browser support below.
- Web frames arrive as BGRA and are not rotated. Frames from every camera except a back one are mirrored, as in the
  `camera` plugin's own Web preview; a laptop webcam usually has no facing mode, is reported as external and is mirrored too.
- Native `yuv420` frames with two planes are NV12 (`Y` + interleaved `UV`); three planes are I420 (`Y`, `U`, `V`).
  One-plane `bgra8888` remains packed. Native row strides are preserved; malformed visible layouts terminate the stream
  through `onError`. YUV conversion uses BT.601 limited/video range; the package does not detect full-range data or select
  another color matrix. The iOS NV12 fixture models plugin bytes only; physical NV12 capture (raw frames, drawn preview and capture, front and back cameras) was verified on an iPhone 11 with iOS 18.7.8, without separate portrait, landscape or mirror NV12 runs.

## What is verified

Backend availability, a successful build and a confirmed physical camera are different things. The checks run directly on
the maintainer's machines with the scripts in `tool/ci/` of the Git repository (the pub.dev archive does not include `tool/`;
the repository has no hosted CI), and their results are recorded
against exact commits. So far they have confirmed:

| Check | Result |
| --- | --- |
| The example's tests | VM coverage includes camera lifecycle, device-check, example navigation, ML Kit input conversion, shape crop, orchestrator and face-screen behavior. Exact test totals are recorded with each gate run. |
| Native capture integration target | Passed with the fake camera platform, no physical camera: on Windows (Release), a physical Pixel 3 (Android 12, `arm64-v8a`, debug and Release builds), Ubuntu 24.04 in a VM, macOS 15.6 (arm64) and the iOS 18.6 simulator. |
| iOS 18.6 simulator fixture targets | Capture, shape-crop and BGRA targets pass on fixtures; no camera is involved. |
| Orchestrator-cycles integration target | Passed with a physical camera: Windows 10 built-in webcam (Release); Chrome (JavaScript build) on Windows with a physical webcam and no fake device; physical Pixel 3 (Android 12, `arm64-v8a`, Release build) with `camera` 0.12.1; a webcam passed through to an Ubuntu 24.04 VirtualBox guest (not attached directly to the Linux machine); macOS 15.6 (arm64) built-in camera. |
| Shape-crop integration target | Passed on the real YUV backend of the platform, without a camera, on the same platforms, devices and modes as the orchestrator-cycles target. |
| Minimum Android dependency | `camera` 0.11.0+2 / CameraX 0.6.30 produced inconsistent physical Pixel 3 preview results (three failed runs and one passing run) and is outside the package dependency range, now `>=0.12.1 <0.13.0`. Physical Pixel 3 preview is verified with `camera` 0.12.1. |
| macOS 15.6 preview check | Passed on the built-in camera: two previews, the second continuing after the first is removed, and final close. |
| Web camera source smoke | Passed in Chrome (JavaScript build) on Windows with a physical webcam. |
| Web device-choice target | Passed in Chrome (JavaScript build) on a fake media stream with two distinct fake video inputs. This is the only fake-stream result; no physical camera is claimed. |
| iPhone 11, iOS 18.7.8 | Orchestrator, camera-flow and BGRA integration targets pass, and the signed Release device check passes (portrait idle and heavy load, landscape, face portrait and landscape, mirror, capture). The operator confirmed two previews, the second continuing after the first is removed, and landscape capture in Shape crop. |
| iOS observation | The behavior documented on `YuvCameraFrame`: one iPhone, iOS 18.7, front camera, portrait and landscape. |

A build, a passing emulator or a fake-stream target does not prove that a physical camera works on that platform. Other
platforms, other browsers (including Safari and Firefox), mobile browsers, `--wasm` builds, other devices and OS versions are not claimed.
The Web evidence is the Windows Chrome JavaScript build served in the default Flutter layout; a custom `assetBase`, a CDN or a
strict Content-Security-Policy for the `yuv_ffi` WebAssembly module, and static CocoaPods linkage on iOS and macOS (see the
`yuv_ffi` documentation), have not been verified. Before each release, every listed result is either run again or carried over from an earlier run when the code it covers has not changed.

## Troubleshooting

### `availableCameras()` returns an empty list

- Symptom: your code shows "no camera" and there is no preview.
- Check: does the device or computer have a camera that other applications can see? On desktop, is `camera_desktop` in
  `pubspec.yaml`, and was the app rebuilt after adding it?
- Action: handle the empty list in your UI, as Getting started does, and connect a camera or add the missing provider.

### `initialize()` throws, or the camera never opens

- Symptom: the exception is caught by your code and you see your own message, or the picture never appears.
- Check: was the permission denied? Compare the setup table above for your platform: Android needs `minSdk` 26 and the
  run-time prompt, iOS and macOS need `NSCameraUsageDescription` (macOS also the entitlement), the browser needs the
  permission on a secure origin. Is another application using the camera?
- Action: fix the setup, then create a new `CameraController` and call `initialize()` again. A controller that failed to
  initialize should be disposed, not reused.

### The preview is replaced by `Camera error: ...`

- Symptom: text starting with `Camera error:` where the preview was, and `onStreamStopped` is called after the stream
  error. Both preview widgets call it only after a stream error, never during removal or controller replacement.
- Check: read the message. `Bad state: CameraController should be initialized` means the controller passed to the view was
  not initialized. Another message is a failure of the frame stream.
- Action: pass an initialized controller. After a stream failure open the camera again with a new controller: the source
  that failed has stopped and the view shows the error until it is rebuilt with a new controller.
  With `YuvCameraOrchestrator`, use `YuvCameraLeaseBuilder`'s Retry action; it drains and disposes the failed controller
  before opening a replacement. Do not start another native image stream on a controller while a YUV source is active.

### The preview stutters or freezes while you process frames

- Symptom: smooth preview until `onFrame` or `transform` does real work.
- Check: heavy synchronous work in `onFrame` or `transform` runs on the UI isolate and stops painting.
- Action: shorten the work, raise `onFrameInterval`, or move the work to another isolate; see
  [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing#how-often-onframe-runs).

### `capture()` returns `null`

- Symptom: the capture button does nothing, or your code reports no image.
- Check: is the view built and attached (you passed its `viewController`)? Was the view or the controller replaced, or the
  stream stopped, before a frame was drawn?
- Action: capture when the preview is visible, keep the page alive while waiting, and show a message for `null`.
  Details: [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture#capture-what-is-on-screen).

### `onFrame` is called less often than expected

- Symptom: your callback runs a few times per second at most.
- Check: `onFrameInterval` defaults to 200 ms, and `onFrame` never overlaps itself: while an async call is pending, frames
  are skipped.
- Action: lower `onFrameInterval` (`Duration.zero` offers every frame) and make the callback return sooner; use
  `YuvCameraFrameSource` for your own pacing.

### Detector boxes or overlays are in the wrong place

- Symptom: boxes are mirrored, rotated or shifted.
- Check: which coordinates are they in, and which matrix maps them?
- Action: map upright boxes with `geometry.uprightToView`; see
  [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays#limits-and-errors).

### The build fails on Linux

- Symptom: the build cannot find GStreamer headers or libraries.
- Check: are the GStreamer development packages installed?
- Action: install `libgstreamer1.0-dev` and `libgstreamer-plugins-base1.0-dev` (or your distribution's equivalent), then
  build again.

### On Web, `availableCameras()` throws `cameraNotReadable`

- Symptom: in Chrome, `availableCameras()` throws a `CameraException` with the code `cameraNotReadable` before any camera is
  chosen, so no preview starts. `YuvCameraOrchestrator.acquire()` ends with the same error, which it keeps as its error
  state instead of hiding it.
- Check: is a virtual camera registered with the system but not running, for example OBS Virtual Camera while OBS is not
  providing it? The `camera_web` versions checked list every device and stop at the first one the browser cannot read.
- Action: start the virtual camera (in OBS, Start Virtual Camera), or turn it off or unregister it so that only working
  cameras remain, then reload the page. `yuv_camera` does not change how the plugin lists or opens devices.

### ML Kit gives no results on desktop or Web

- Symptom: the example's face detection does nothing on Windows, macOS, Linux or Web.
- Check: the example runs ML Kit face detection only on Android and iOS and skips it elsewhere.
- Action: wire a detector that supports your platform, or run detection only on Android and iOS as the example does.

## Related pages

- [Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started): the first working preview.
- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): throttling and heavy work.
- [yuv_ffi: Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting): initialization, native library and Web module errors.

## Verification boundaries

The declared Flutter floor is 3.44.0; recorded release validation used Flutter 3.44.9, so it does not independently
verify the minimum SDK. Safari, Firefox and mobile Web are unverified. Custom asset placement, CDN hosting and strict
CSP for the WASM module, and static CocoaPods linkage, remain unverified.
Camera Web evidence covers Chrome JavaScript; camera `--wasm` is not claimed. A desktop camera provider does not
prove physical capture support. Physical iPhone NV12 front/back preview and capture evidence does not establish
separate NV12 landscape or mirror support.
