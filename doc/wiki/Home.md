# yuv_camera wiki

`yuv_camera` shows a live camera preview in Flutter, hands each camera frame to your code as a `YuvImage`, and captures
the frame that is actually on screen. It is built on the [`camera`](https://pub.dev/packages/camera) plugin and on
[`yuv_ffi`](https://github.com/Anfet/yuv_ffi), and has no native plugin, platform channel or FFI layer of its own. These
guides give step-by-step recipes, explain the behavior behind them and list the errors you are most likely to meet. The
[README](https://github.com/Anfet/yuv_camera#readme) is the quick start, the
[API reference](https://pub.dev/documentation/yuv_camera/latest/) lists every parameter, and the
[CHANGELOG](https://github.com/Anfet/yuv_camera/blob/main/CHANGELOG.md) records what changed in each version.

**Documented version: 0.0.1.** This wiki describes `yuv_camera` 0.0.1, the first version of the package, which
requires `yuv_ffi: ^0.5.2`. Every recipe here was built against these two versions.

Image formats, operations and display of images without a camera are covered by the
[yuv_ffi wiki](https://github.com/Anfet/yuv_ffi/wiki). Read it for what a `YuvImage` can do once you hold one.

## Choose a route

### First result

You want a camera preview on screen, then a captured picture.

1. [Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started): set up the platform, add the packages
   and show the preview.
2. [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): own the camera controller and
   capture the frame the user sees.

### Typical scenario

Your screen processes camera frames (face detection, filters, measurements) and draws results over the preview.

1. [Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started): a working preview.
2. [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): receive frames in `onFrame`, use the
   raw and upright images, avoid mutating a delivered frame, connect ML Kit, or change what is drawn.
3. [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays): put boxes over the
   preview in the right place.
4. [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): capture the processed screen.
5. [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting):
   permissions, desktop and Web setup, verified platforms and fixes.

## All guides

| Guide | Use it to |
| --- | --- |
| [Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started) | Install, set up permissions and show a preview. |
| [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture) | Own and dispose the camera controller, switch cameras, and capture the drawn frame. |
| [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing) | Process frames with `onFrame`, read every frame with a frame source, wire ML Kit and transform the preview. |
| [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays) | Map detector boxes to the preview; understand camera orientation per platform. |
| [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting) | Set up permissions, desktop provider and Web; see what is verified; fix common failures. |

## The five public types

Everything is exported from `package:yuv_camera/yuv_camera.dart`.

| Type | Purpose | Guide |
| --- | --- | --- |
| `YuvCameraView` | A preview widget that also delivers throttled frames to `onFrame`, builds overlays and serves capture. | [Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started), [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture) |
| `YuvCameraViewController` | A handle for one view: `capture()` and the current `geometry`. | [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture) |
| `YuvCameraFrame` | One immutable camera delivery with the raw `image`, the `upright()` image and the `orientation`. | [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing) |
| `YuvCameraFrameSource` | A stream of every frame without a preview widget; throttling is yours. | [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing#read-every-frame-without-a-preview) |
| `YuvTransformView` | A preview that runs a synchronous function on each accepted frame and draws its result. | [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing#change-what-is-drawn) |

## Related

- [Example app](https://github.com/Anfet/yuv_camera/tree/main/example): a camera screen with capture, an ML Kit
  face-detection screen and a device-check screen.
- [yuv_ffi wiki](https://github.com/Anfet/yuv_ffi/wiki): formats, operations, display and geometry of images.
- Plugin documentation: [`camera`](https://pub.dev/packages/camera) and
  [`camera_desktop`](https://pub.dev/packages/camera_desktop).
