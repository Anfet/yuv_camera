# Migrating the yuv_ffi example camera code to yuv_camera 0.0.1

`yuv_ffi 0.5.2` keeps its public image API. Its example no longer contains the camera layer or the ML Kit demo;
these now live in `yuv_camera`. This guide is for applications that copied that example code. Image-only applications
can update `yuv_ffi` without adding camera dependencies.

## Dependencies and imports

Add the dependencies from [README.md](README.md#installation). On desktop add `camera_desktop` beside `camera`, then
rebuild the application: Flutter registers the federated plugin. No manual registration call is needed.

Replace imports of the copied camera views, controllers, frames and sources with:

```dart
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
```

Import `package:camera/camera.dart` when constructing a `CameraController` yourself. `yuv_camera` does not re-export
the `camera` package. `YuvCameraView`, `YuvCameraViewController`, `YuvCameraFrame`, `YuvCameraFrameSource` and
`YuvTransformView` retain their names. Stop importing `package:yuv_ffi_example/camera/...` or depending on
`package:yuv_camera/src/...`; frame import and orientation helpers are implementation details.

## Camera ownership and lifecycle

Choose one owner for each controller:

- Keep your application's initialized `CameraController`, pass it to `YuvCameraView` or `YuvTransformView`, and stop
  the view before disposing the controller. Your application handles camera permissions, failures and lifecycle.
- Use `YuvCameraOrchestrator` with `YuvCameraLeaseBuilder`, as in the complete README Quick start. The builder obtains
  a lease, removes its child before releasing the lease, releases while hidden, and reacquires when shown. Dispose
  the orchestrator when its owner is removed; dispose the separate view controller too. Manually acquired leases
  must be released by the application when no longer needed or when it goes to the background.

If you copied the development-stage `YuvCameraOrchestratorView`, replace it with `YuvCameraLeaseBuilder` and supply
`builder: (context, controller) => YuvCameraView(cameraController: controller, ...)`. The former wrapper was not a
released package API. Orchestrator notifications are coalesced in a microtask; listeners read its current getters.

`onStreamStopped` on both preview widgets reports a stream error. It does not report ordinary removal or controller
replacement. Remove application code that used that callback as its normal disposal signal.

With an active YUV source, the source owns native frame delivery. Do not also call `startImageStream`, start video
recording with `onAvailable`, or subscribe directly to platform frames on that controller. If a `YuvCameraOrchestrator`
controller reports a terminal error, its leases are invalidated and the controller is disposed after stream cancellation
finishes. `YuvCameraLeaseBuilder` then offers Retry, which opens a new controller without route navigation. A manually
owned controller remains the application's responsibility after `onStreamStopped`.

## Frames and capture

Native sources accept the plugin's default image format, `ImageFormatGroup.yuv420`, or `ImageFormatGroup.bgra8888`.
Two-plane `yuv420` is imported as NV12; three-plane `yuv420` is imported as I420; one-plane BGRA remains packed.
Plane strides and layouts are preserved. Malformed plane layouts stop the stream and report a `FormatException`; an
unsupported format group reports `UnsupportedError`. YUV conversion uses BT.601 limited/video range as defined by
`yuv_ffi`; full-range data and other color matrices are not detected. Do not request `ImageFormatGroup.nv21` for this source; choose the default or a supported group. Physical NV12 capture (raw frames, drawn preview and capture) was verified for the front and back cameras on an iPhone 11 with iOS 18.7.8. Separate NV12 landscape and mirror runs were not performed.

`onFrame` receives a `YuvCameraFrame`. Its `image` preserves source plane strides; `upright()` returns a cached packed,
oriented image. Both belong to the delivery: call `copy()` before mutating either. Call `YuvFfi.initialize()` before
processing, as in the README.

`capture()` returns the next drawn frame, cropped and oriented to the visible region. Its result is owned by the
application. Handle `null` when the view is detached or stops before a pending capture completes. It has no built-in
timeout: while the view remains attached but no frame is drawn, the future can stay pending. Remove the view to cancel
its pending capture. Repeated calls while one capture is pending share its future. Use `viewController.geometry` for
overlays in the displayed coordinate space; it is `null` before a frame is drawn and while the view is detached or
switching controllers.

On Android, `YuvCameraFrame.orientation` follows the current device orientation and camera sensor orientation. Calling
the camera plugin's `lockCaptureOrientation()` does not lock the orientation reported for these YUV preview frames.
For a camera switch, remove the view and create and initialize a new `CameraController` for the selected description;
changing `description` in place stops the active YUV source and is not a seamless switch.

On Web the source uses a second stream, matching the initialized controller's unique, non-empty device label; it falls
back to lens direction for missing or ambiguous labels. Resolution and FPS are browser preferences. Test your real
device and handle permission or stream-opening failures; Chrome JavaScript evidence does not establish Safari,
Firefox or camera `--wasm` support.

## ML Kit stays in the application

`google_mlkit_face_detection`, the input adapter and heavy processing are example/application code, not package
dependencies. Connect them through `onFrame`. The example's `toInputImage` packs YUV as actual NV21 (VU order) for
ML Kit and uses the frame rotation; the historical `yuv_ffi` factory named `nv21` meant UV order and must map to
`YuvPixelFormat.nv12`, as described in the [image migration guide](https://github.com/Anfet/yuv_ffi/blob/main/MIGRATION.md).

For BGRA captured images the example pads ML Kit input to a width divisible by four without changing the captured
image. This is a workaround verified on the documented iPhone configuration, not a universal SDK requirement.
ML Kit runs on Android and iOS in this example; provide your own detector for desktop or Web.

## Verify the application

Run `flutter pub get`, `flutter analyze`, and your application's tests. Check real-camera preview, capture,
navigation away and back, background/resume, denied permissions and stream failure on the platforms you ship.
Confirm Android `minSdk >= 26`, iOS/macOS usage descriptions, macOS camera entitlement and the desktop provider;
see [platform setup](README.md#platform-setup).

For local paired development from Git checkouts, use ignored `pubspec_overrides.yaml` files as shown in the README, or
run `tool/check_pair.ps1` for an exact pair. These checks validate that local pair only. To check a hosted release, remove
the overrides, run `flutter pub get`, and confirm that `.dart_tool/package_config.json` resolves both packages from
`hosted/pub.dev`.

## Preview host and shader reporting

Await `YuvFfi.initialize()` in each isolate before image processing or capture. Host previews in standard Flutter
text and theme context, normally `MaterialApp` / `Scaffold`; stream errors show English `Camera error: ...` text.
`onFramePresented(bool)` reports a drawn frame and shader availability. A `true` flag does not establish shader paint:
BGRA and unsupported/gapped layouts can use fallback. Device check JSON schema 1 uses the same meaning for `shader`.
