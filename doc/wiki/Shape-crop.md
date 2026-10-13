# Shape crop

**Task:** cut a rectangle, a square, an oval or a circle out of a captured picture, for example a round avatar or a face
region, and get it either as a `YuvImage` or as BGRA bytes that are transparent outside the shape.

**Conditions:** a `YuvImage`, usually the one returned by `capture()` on
[Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture), and a completed
`await YuvFfi.initialize()` (the cut uses the same crop as the [yuv_ffi](https://github.com/Anfet/yuv_ffi/wiki)
operations). The cut works on any `YuvImage`, so you can try it first without a camera.

## The three parts

`image.croppedToShape(target, shape: ..., fill: ...)` combines a target, a shape and a fill color.

| Part | Choices |
| --- | --- |
| `YuvCropTarget`: where the rectangle is | `YuvCropTarget.pixels(size)`: a box of exactly `size` pixels. `YuvCropTarget.fraction(left:, top:, right:, bottom:)`: edges as fractions of the width and height, the whole image by default. `YuvCropTarget.square(side)`: a square whose side is `side` times the smaller image side, `side` in `(0, 1]`. `pixels` and `square` also take `alignment` (centered by default) and `offset` (a shift in pixels). |
| `YuvCropShape`: what stays visible in it | `rectangle` (default): the whole rectangle. `ellipse`: the ellipse inscribed in the rectangle. |
| `fill`: what covers the rest | A `Color` painted outside the shape in the result's `image`; black by default, its alpha is ignored. |

A target works in image pixels and knows nothing about rotation, screen scale or widgets, so a picture from
`capture()` can be used as it is. A box larger than the image is scaled down to fit with its proportions kept, and a box
is never placed outside the image: an `offset` that pushes it out stops at the nearest edge.

The four usual shapes are combinations:

| You want | Target | Shape |
| --- | --- | --- |
| Rectangle with free width and height | `YuvCropTarget.pixels(size)` | `YuvCropShape.rectangle` |
| Square | `YuvCropTarget.square(side)` | `YuvCropShape.rectangle` |
| Oval, for example a vertical, face-shaped one | `YuvCropTarget.pixels(size)`, taller than wide | `YuvCropShape.ellipse` |
| Circle | `YuvCropTarget.square(side)` | `YuvCropShape.ellipse` |

## What you get back

`croppedToShape` returns a `YuvShapedImage` and leaves the source image unchanged.

| Member | Meaning |
| --- | --- |
| `image` | The cut-out rectangle in the format of the source, an independent copy that you own. Points outside the shape hold `fill`. |
| `shape`, `fill` | What you passed. |
| `region` | Where `image` was cut from, in pixels of the source. |
| `insideCount` | How many points of `image` are inside the shape. |
| `contains(x, y)` | Whether the point `(x, y)` of `image` is inside the shape; a point outside `image` is not. |
| `toBgraBytes()` | A new buffer of exactly `width * height * 4` BGRA bytes where points outside the shape have alpha 0. |

Transparency follows the shape, not a key color: a `fill` color that also appears in the picture does not become
transparent. For I420 and NV12 a chroma sample is painted only when every point it covers (up to 2x2) is outside the
shape; otherwise it keeps the color of the image.

## Try it without a camera

This recipe cuts a circle out of a plain red 640x480 image and prints what comes back.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Cuts a circle out of a plain red 640x480 image and prints what comes back.
Future<void> shapeCropNumbers() async {
  await YuvFfi.initialize();
  const width = 640;
  const height = 480;
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = 255; // red
    rgba[i + 3] = 255; // opaque
  }
  final source = YuvImage.fromRgbaBytes(rgba, width: width, height: height, format: YuvPixelFormat.i420);

  final circle = source.croppedToShape(const YuvCropTarget.square(0.5), shape: YuvCropShape.ellipse, fill: const Color(0xFF00FF00));
  debugPrint('region ${circle.region}');
  debugPrint('size ${circle.image.width}x${circle.image.height}');
  debugPrint('inside ${circle.insideCount} of ${circle.image.width * circle.image.height}');
  debugPrint('corner inside ${circle.contains(0, 0)}, center inside ${circle.contains(120, 120)}');

  final bgra = circle.toBgraBytes();
  debugPrint('alpha at the corner ${bgra[3]}, at the center ${bgra[(120 * 240 + 120) * 4 + 3]}');
  debugPrint('source still ${source.width}x${source.height}');
}
```

Expected result, the numbers the page was written with:

```text
region Rect.fromLTRB(200.0, 120.0, 440.0, 360.0)
size 240x240
inside 45244 of 57600
corner inside false, center inside true
alpha at the corner 0, at the center 255
source still 640x480
```

The side of the square is half of the smaller image side (480), so it is 240 pixels, and it is centered in the 640
pixel width. About `pi * 120 * 120` points are inside the circle.

## Capture and cut

This recipe adds a button to a preview. It captures the frame on screen, cuts a circle out of its center and shows the
result under the preview. Pass an initialized controller, and call `await YuvFfi.initialize()` once before, for example
in `main`.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A preview with a button that captures a frame and cuts a circle out of its center; [controller] must be initialized.
class CircleCutPanel extends StatefulWidget {
  const CircleCutPanel({super.key, required this.controller});

  final CameraController controller;

  @override
  State<CircleCutPanel> createState() => _CircleCutPanelState();
}

class _CircleCutPanelState extends State<CircleCutPanel> {
  final YuvCameraViewController _view = YuvCameraViewController();
  YuvShapedImage? _cut;
  String _status = 'Press the button to capture and cut.';
  bool _busy = false;

  Future<void> _captureAndCut() async {
    setState(() => _busy = true);
    try {
      final image = await _view.capture();
      if (!mounted) return;
      if (image == null) {
        setState(() => _status = 'Nothing was captured: the view is not attached or stopped first.');
        return;
      }
      final cut = image.croppedToShape(const YuvCropTarget.square(0.5), shape: YuvCropShape.ellipse);
      final region = cut.region;
      setState(() {
        _cut = cut;
        _status =
            'Cut ${cut.image.width}x${cut.image.height} from (${region.left.toInt()}, ${region.top.toInt()}), '
            '${cut.insideCount} of ${cut.image.width * cut.image.height} points inside.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Cut failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: YuvCameraView(cameraController: widget.controller, viewController: _view),
          ),
          Padding(padding: const EdgeInsets.all(8), child: Text(_status)),
          if (_cut case final cut?)
            SizedBox(
              height: 120,
              width: double.infinity,
              child: YuvImageWidget(image: cut.image, boxFit: BoxFit.contain),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _busy ? null : _captureAndCut, child: const Icon(Icons.crop_free)),
    );
  }
}
```

Expected result: after pressing the button a line such as `Cut 240x240 from (200, 120), 45244 of 57600 points inside.`
(the numbers depend on the size of your camera frame) appears with the circle under the preview; the corners are black
because black is the default `fill`. Use `cut.toBgraBytes()` for the transparent version, for example to give it to an
image encoder that supports alpha. This recipe was compiled and analyzed for Windows and Web; the project has not run it
on a physical camera, so test it on your target devices.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| `ArgumentError` mentioning `side` | `YuvCropTarget.square` needs `side` in `(0, 1]`: a fraction of the smaller image side, not pixels. |
| `ArgumentError` mentioning `size` | `YuvCropTarget.pixels` needs a finite size of at least one pixel in both directions after rounding. |
| `ArgumentError: fraction edges must satisfy ...` or `fraction box rounds to under one pixel` | For `YuvCropTarget.fraction` keep `0 <= left < right <= 1` and `0 <= top < bottom <= 1`, and leave at least one pixel between the edges of the image. |
| `ArgumentError` for `alignment` or `offset` | They must be finite numbers. |
| `UnsupportedError: YuvFfi.initialize() must complete before ...` or a `StateError` asking for `YuvFfi.initialize()` | `await YuvFfi.initialize()` has not completed in the isolate that cuts (Web always needs it); see [yuv_ffi: Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting#initialize-in-every-isolate). |
| The circle is an oval | The target was not square: use `YuvCropTarget.square`, not `YuvCropTarget.pixels` with different sides. A box larger than the image is scaled to fit, so a large `pixels` size keeps its proportions. |
| Black corners remain in the file you saved | `image` holds `fill` outside the shape; use `toBgraBytes()` and an encoder with alpha, or choose another `fill`. |
| The cut is slow in a frame callback | The cut is synchronous and runs on the UI isolate. Cut a captured picture on a user action, not on every frame. |

## Related pages

- [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): get the picture with `capture()`.
- [Sharing the camera](https://github.com/Anfet/yuv_camera/wiki/Sharing-the-camera): open the camera for several screens.
- [yuv_ffi: Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): the crop and the other operations on a `YuvImage`.
- [yuv_ffi: Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): show a `YuvImage`.
- The example app's [Shape crop screen](https://github.com/Anfet/yuv_camera/blob/main/example/lib/shape_crop/shape_crop_screen.dart).
