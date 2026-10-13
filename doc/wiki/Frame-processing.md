# Frame processing

**Task:** run your own code on camera frames (measure, filter, detect), keep the preview smooth, and avoid corrupting
the frames the preview and `capture()` use.

**Conditions:** a working preview ([Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started)). The
recipes are widgets that take an initialized `CameraController`. What you can do with a `YuvImage` once you hold one is in
the [yuv_ffi wiki](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations).

## What a frame is

`onFrame` receives a `YuvCameraFrame`: one immutable delivery from the camera.

| Member | Meaning |
| --- | --- |
| `width`, `height` | Size in pixels of the raw image. |
| `format` | Pixel format of the raw image: `YuvPixelFormat.i420` or `YuvPixelFormat.bgra8888`, depending on what the camera delivers. |
| `orientation` | A `YuvFrameOrientation`: how the raw image must be rotated, and whether mirrored, to appear upright. |
| `timestamp` | Time since the frame source started. It restarts when the source starts again. |
| `image` | The raw camera image as a `YuvImage`, imported on first access and cached. The camera's plane strides are preserved. |
| `upright()` | A packed (tight) image with the orientation applied, computed on first call and cached. |

`image` is imported on first access and `upright()` on its first call; both results are cached on the frame, so asking
again returns the same object.

### Raw or upright

| Use | When |
| --- | --- |
| `frame.image` | You pass the frame to a library that takes the raw pixels together with a rotation (ML Kit does), or you only read planes. Combine it with `frame.orientation`. |
| `frame.upright()` | You work on pixels yourself and want the picture the right way up: measuring, filters, crops, saving. The first call copies, packs and rotates the frame, so call it once per frame and reuse the result. |

On Android the orientation is derived from the sensor and the device orientation. On Windows and Web frames are not
rotated and are mirrored for every camera except a back one; on iOS, macOS and Linux they arrive upright and not
mirrored. The rules are in [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays#how-orientation-is-derived).

## Do not mutate a delivered frame

A frame, its `image` and its `upright()` image belong to the delivery. The preview and `capture()` read the delivered
`image`, so a change to it can leak into them, and `upright()` is cached and shared by everything that reads the frame.
Call `copy()` before an in-place operation:

```dart
final working = frame.upright().copy().applyGrayscale();
```

This recipe measures the average brightness of the frames. It works on a grayscale copy and leaves the delivered image
alone.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// A preview that reports the average brightness of the camera frames; [controller] must be initialized.
class BrightnessMeter extends StatefulWidget {
  const BrightnessMeter({super.key, required this.controller});

  final CameraController controller;

  @override
  State<BrightnessMeter> createState() => _BrightnessMeterState();
}

class _BrightnessMeterState extends State<BrightnessMeter> {
  double? _brightness;

  void _onFrame(YuvCameraFrame frame) {
    final gray = frame.upright().copy().applyGrayscale();
    final bytes = gray.toBgraBytes();
    var sum = 0;
    var count = 0;
    for (var i = 1; i < bytes.length; i += 64) {
      sum += bytes[i]; // green channel; equal to the others after grayscale
      count++;
    }
    if (mounted) setState(() => _brightness = sum / count);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _brightness;
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvCameraView(cameraController: widget.controller, onFrame: _onFrame, onFrameInterval: const Duration(milliseconds: 500)),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Text(
              brightness == null ? 'Measuring...' : 'Brightness ${brightness.toStringAsFixed(0)} of 255',
              style: const TextStyle(color: Colors.white, backgroundColor: Colors.black54, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}
```

Expected result: the preview with a caption that updates about twice a second and falls when you cover the lens.
`upright()` is cached per frame, so calling it again for the same frame is free, and `copy()` makes the mutation
private.

## How often `onFrame` runs

- `onFrameInterval` (default 200 ms) is the minimum time between two calls, measured on the frames' `timestamp`. A frame
  that arrives sooner is not delivered to `onFrame`. Pass `Duration.zero` to be offered every frame.
- `onFrame` never overlaps itself. It may return a `Future`; while that future is pending, further frames are skipped
  for `onFrame`. So a slow callback lowers the callback rate, not the preview rate.
- The preview does not depend on `onFrame`. It presents frames at its own pace: a new frame is accepted only after the
  previous one has been drawn, and frames that arrive in between are dropped.
- An error thrown by `onFrame` (or failing in its future) is reported through `FlutterError.reportError` with the library
  name `yuv_camera`; the stream keeps running.
- Everything in `onFrame` that is not awaited runs on the UI isolate. **Heavy synchronous work blocks the UI isolate
  and stops painting**, preview included. Keep the callback short, or move heavy work to another isolate: send bytes and
  sizes, initialize `yuv_ffi` there and send results back, as in
  [yuv_ffi: Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting#initialize-in-every-isolate).

## Read every frame without a preview

`YuvCameraFrameSource` delivers every frame and leaves throttling to you; use it when no preview is shown, or when you
need your own pacing. `YuvCameraView` and `YuvTransformView` create their own sources, so you do not start one for them.
This recipe counts the frames the camera delivers per second.

```dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// Shows how many frames per second the camera delivers; [controller] must be initialized.
class FrameRate extends StatefulWidget {
  const FrameRate({super.key, required this.controller});

  final CameraController controller;

  @override
  State<FrameRate> createState() => _FrameRateState();
}

class _FrameRateState extends State<FrameRate> {
  late final YuvCameraFrameSource _source = YuvCameraFrameSource(widget.controller, onFrame: _onFrame, onError: _onError);
  Duration _windowStart = Duration.zero;
  int _frames = 0;
  String _text = 'Waiting for frames...';

  @override
  void initState() {
    super.initState();
    unawaited(_source.start());
  }

  void _onFrame(YuvCameraFrame frame) {
    _frames++;
    final elapsed = frame.timestamp - _windowStart;
    if (elapsed >= const Duration(seconds: 1)) {
      final rate = _frames * 1000 / elapsed.inMilliseconds;
      _windowStart = frame.timestamp;
      _frames = 0;
      if (mounted) setState(() => _text = 'Camera delivers ${rate.toStringAsFixed(1)} frames per second');
    }
  }

  void _onError(Object error) {
    if (mounted) setState(() => _text = 'The frame stream stopped: $error');
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(_text)));
}
```

Expected result: a text line that is refreshed every second and shows the delivery rate of the camera (it is the number
of frames the camera sends, which is not the rate at which a preview draws them).

`start()` replaces any running delivery, `stop()` pauses it (you can call `start()` again) and `dispose()` ends it for
good. After a stream error the source has already stopped, and `onError` is called once.

## Change what is drawn

`YuvTransformView` shows the camera like `YuvCameraView`, but draws the image that your `transform` returns for each
accepted frame. `transform` is synchronous and runs on the UI isolate. It returns an upright `YuvImage`; the view copies
what it draws, so you may return an image you will mutate again later.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// A black-and-white preview; [controller] must be initialized.
class GrayscalePreview extends StatelessWidget {
  const GrayscalePreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return YuvTransformView(cameraController: controller, transform: (frame) => frame.upright().copy().applyGrayscale());
  }
}
```

Expected result: a black-and-white preview. A frame arriving while the previous one is still being drawn is not
transformed. If `transform` throws, only that frame is dropped, the error is reported through `FlutterError.reportError`
and the stream continues. Keep `transform` fast: it blocks the UI isolate. `YuvTransformView` has no `viewController`,
so it offers no `capture()`; use `YuvCameraView` when you need capture.

## Use an external detector (ML Kit)

ML Kit is not a dependency of `yuv_camera`. You connect a detector yourself through `onFrame`, as the
[example app](https://github.com/Anfet/yuv_camera/blob/main/example/lib/faces/face_screen.dart) does. The steps:

1. Add the detector to your app (this recipe uses `google_mlkit_face_detection`).
2. In `onFrame`, give the detector the raw `frame.image` and the rotation from `frame.orientation.rotation`. Mirroring is
   not given to the detector.
3. The detector returns boxes in upright coordinates. Draw them with the `overlayBuilder` geometry; see
   [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays).

The raw image may have padded rows, so the recipe packs a copy and writes the NV21 layout that ML Kit expects.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Converts a raw camera [YuvImage] into an ML Kit input without changing it.
InputImage toInputImage(YuvImage image, InputImageRotation rotation) {
  final tight = image.copy().pack();
  if (image.format == YuvPixelFormat.bgra8888) {
    return InputImage.fromBytes(
      bytes: tight.yPlane.bytes,
      metadata: InputImageMetadata(size: image.size, rotation: rotation, format: InputImageFormat.bgra8888, bytesPerRow: image.width * 4),
    );
  }
  return InputImage.fromBytes(
    bytes: _nv21Bytes(tight),
    metadata: InputImageMetadata(size: image.size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: image.width),
  );
}

Uint8List _nv21Bytes(YuvImage tight) {
  final chromaCount = ((tight.width + 1) ~/ 2) * ((tight.height + 1) ~/ 2);
  final vu = Uint8List(chromaCount * 2);
  if (tight.format == YuvPixelFormat.nv12) {
    final uv = tight.uPlane.bytes;
    for (var i = 0; i < chromaCount; i++) {
      vu[i * 2] = uv[i * 2 + 1];
      vu[i * 2 + 1] = uv[i * 2];
    }
  } else {
    final u = tight.uPlane.bytes;
    final v = tight.vPlane.bytes;
    for (var i = 0; i < chromaCount; i++) {
      vu[i * 2] = v[i];
      vu[i * 2 + 1] = u[i];
    }
  }
  final luma = tight.yPlane.bytes;
  return Uint8List(luma.length + vu.length)
    ..setRange(0, luma.length, luma)
    ..setRange(luma.length, luma.length + vu.length, vu);
}

/// A preview with a rectangle around the largest detected face; [controller] must be initialized.
class FaceBoxes extends StatefulWidget {
  const FaceBoxes({super.key, required this.controller});

  final CameraController controller;

  @override
  State<FaceBoxes> createState() => _FaceBoxesState();
}

class _FaceBoxesState extends State<FaceBoxes> {
  FaceDetector? _detector;
  Rect? _face;

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _onFrame(YuvCameraFrame frame) async {
    if (!_supported) return;
    final rotation = switch (frame.orientation.rotation) {
      YuvImageRotation.rotation0 => InputImageRotation.rotation0deg,
      YuvImageRotation.rotation90 => InputImageRotation.rotation90deg,
      YuvImageRotation.rotation180 => InputImageRotation.rotation180deg,
      YuvImageRotation.rotation270 => InputImageRotation.rotation270deg,
    };
    final detector = _detector ??= FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
    final faces = await detector.processImage(toInputImage(frame.image, rotation));
    if (!mounted) return;
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
    setState(() => _face = faces.firstOrNull?.boundingBox);
  }

  @override
  void dispose() {
    _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YuvCameraView(
      cameraController: widget.controller,
      onFrame: _onFrame,
      overlayBuilder: (context, geometry) {
        final face = _face;
        return face == null ? const SizedBox.shrink() : CustomPaint(painter: _FacePainter(geometry, face));
      },
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.geometry, this.face);

  final YuvFrameGeometry geometry;
  final Rect face;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      MatrixUtils.transformRect(geometry.uprightToView, face),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.green,
    );
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) => oldDelegate.geometry != geometry || oldDelegate.face != face;
}
```

Expected result: on Android and iOS a green rectangle follows the largest face in the picture, and nothing is drawn
elsewhere because the recipe skips detection on other platforms (the example app does the same). The detection itself is
ML Kit's; this recipe was compiled and analyzed for Windows and Web, and the project has not run it on a physical
camera for this guide.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| The preview stutters or freezes while processing | Your `onFrame` (or `transform`) does heavy synchronous work on the UI isolate. Shorten it, raise `onFrameInterval`, or move the work to another isolate. |
| `onFrame` runs less often than the camera delivers | By design: at most once per `onFrameInterval` and never overlapping. Lower the interval or use `Duration.zero`; a slow async callback still skips frames while it runs. |
| Pixels look altered, or the preview shows your filter | A delivered image was mutated. Call `copy()` first. |
| `UnsupportedError` saying `YuvFfi.initialize()` must complete | `upright()` or another operation ran before `await YuvFfi.initialize()` (or in an isolate that never called it). |
| `Camera error: ...` replaces the preview | The frame stream failed. See [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting). |
| Detector boxes are shifted or rotated | You passed the wrong rotation, mapped them with the wrong matrix, or gave the detector an already upright image together with a rotation. See [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays). |

## Related pages

- [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays): put results over the preview.
- [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): capture after processing.
- [yuv_ffi: Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): everything you can do to a `YuvImage`.
