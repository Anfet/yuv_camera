# Geometry and overlays

**Task:** draw boxes, marks or hit areas over the camera preview so they stay on the right part of the picture whatever the
device orientation, camera or fit.

**Conditions:** a `YuvCameraView` ([Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started)) and results
that are expressed in the upright frame (a detector's bounding boxes, for example). The coordinate model is the one of
`yuv_ffi`; this page applies it to a camera, and the
[yuv_ffi page](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays) explains the matrices in depth.

## The geometry of the displayed frame

`YuvCameraView` computes a `YuvFrameGeometry` for the frame it draws and gives it to you in two ways:

- `overlayBuilder: (context, geometry) => ...` builds a widget stacked over the preview. It is called only once a frame has
  been drawn and the geometry is known, and it is rebuilt when the geometry changes.
- `viewController.geometry` is a `ValueListenable<YuvFrameGeometry?>`: `null` until the first frame is drawn, after the
  view is detached, and while it switches controllers; otherwise it holds the current geometry. Use it outside the
  overlay, for example to show or hit-test things elsewhere.

Always map through the geometry you are given. It already contains the fit (`cover` by default), the alignment, the
rotation and the mirror of the current frame.

| You have | Map it with |
| --- | --- |
| A box from a detector that was given the raw frame and `orientation.rotation` (upright coordinates) | `MatrixUtils.transformRect(geometry.uprightToView, box)` |
| A point in raw camera pixels | `geometry.sourceToView` |
| A tap position in the view, to find the camera pixel under it | `MatrixUtils.transformPoint(geometry.viewToSource, position)` |
| The part of the camera frame that is visible | `geometry.visibleSourceRect` (smaller than the frame with `cover`) |

## Draw a box in the right place

This recipe draws a rectangle around the central half of the upright frame and prints the visible part of the raw frame
under the preview. The rectangle stays centered on the picture for every orientation, which shows that the mapping works.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// A preview with a rectangle on the central half of the upright frame; [controller] must be initialized.
class CenterBox extends StatefulWidget {
  const CenterBox({super.key, required this.controller});

  final CameraController controller;

  @override
  State<CenterBox> createState() => _CenterBoxState();
}

class _CenterBoxState extends State<CenterBox> {
  final YuvCameraViewController _view = YuvCameraViewController();

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        YuvCameraView(
          cameraController: widget.controller,
          viewController: _view,
          overlayBuilder: (context, geometry) => CustomPaint(painter: _CenterBoxPainter(geometry)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: ValueListenableBuilder<YuvFrameGeometry?>(
              valueListenable: _view.geometry,
              builder: (context, geometry, _) => Text(
                geometry == null ? 'No frame yet' : 'Visible part of the camera frame: ${geometry.visibleSourceRect}',
                style: const TextStyle(color: Colors.white, backgroundColor: Colors.black54),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CenterBoxPainter extends CustomPainter {
  _CenterBoxPainter(this.geometry);

  final YuvFrameGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final source = geometry.sourceSize;
    final upright = geometry.orientation.rotation.swapSize ? Size(source.height, source.width) : source;
    final box = Rect.fromCenter(center: upright.center(Offset.zero), width: upright.width / 2, height: upright.height / 2);
    canvas.drawRect(
      MatrixUtils.transformRect(geometry.uprightToView, box),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.green,
    );
  }

  @override
  bool shouldRepaint(_CenterBoxPainter oldDelegate) => oldDelegate.geometry != geometry;
}
```

Expected result: a green rectangle centered on the preview, covering half the width and half the height of the frame as
the user sees it, and a caption under it with the visible area in raw camera pixels. If you rotate the device, the
rectangle stays on the same part of the picture. A detector box is drawn the same way: replace `box` with the box that
ML Kit returned for the frame (see [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing#use-an-external-detector-ml-kit)).

## How orientation is derived

`YuvCameraFrame.orientation` tells how the raw image must be rotated, and whether mirrored, to be upright. The frame source
fills it from the platform:

| Platform | Orientation of the raw frame |
| --- | --- |
| Android | Computed from the camera's sensor orientation and the device orientation (below). |
| Windows, Web | Not rotated. Mirrored for every camera except a back one, as the camera plugins' own previews are. On Windows `camera_desktop` reports every camera as front; in a browser a camera without a facing mode, such as a laptop webcam, is reported as external. |
| iOS, macOS, Linux | Upright and not mirrored: no rotation is applied. |

On Android the device orientation maps to degrees (`portraitUp` 0, `landscapeLeft` 90, `portraitDown` 180,
`landscapeRight` 270) and the camera direction decides the rest:

| Camera | Rotation (clockwise) | Mirrored |
| --- | --- | --- |
| Front | `(sensorOrientation + deviceDegrees) % 360` | Yes |
| Back or external | `(sensorOrientation - deviceDegrees + 360) % 360` | No |

For example a back camera whose sensor orientation is 90 in `portraitUp` gets rotation 90. These formulas and the Windows and Web
rule are covered by the package's unit tests. The iOS behavior was observed with the front camera on one iPhone running iOS 18.7 in portrait
and landscape; that observation is limited to that configuration, and no other device or platform is claimed beyond the
[verified list](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting#what-is-verified).

Mirroring is applied after rotation, which is why a detector gets the rotation only: it works in upright coordinates and you
map its result with `uprightToView`, which includes the mirror.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| The box is mirrored or on the wrong side | You mapped upright coordinates with `sourceToView`, or you applied your own mirror. Use `uprightToView` and nothing else. |
| The box is rotated 90 degrees from the face | The detector was given the wrong rotation, or an already upright image together with `frame.orientation.rotation`. Give the raw frame (`frame.image`) with its rotation, or `frame.upright()` with no rotation, not both. |
| The overlay is missing at first | `overlayBuilder` runs only after a frame has been drawn. This is expected for the first moments. |
| The box is offset when the preview is cropped | Compare `fit`: with `cover` part of the frame is outside the view. Boxes are mapped correctly, but a box near the frame's edge can lie outside the view. Use `geometry.visibleSourceRect` to test visibility. |
| The overlay lags behind the picture | The detector result describes an older frame. The geometry is the current one; for a fast-moving subject, accept some lag or process more often. |
| `viewController.geometry` is `null` | No frame has been drawn yet, the view is detached, or it is switching controllers. Listen to the notifier and use the value once it arrives. |

## Related pages

- [yuv_ffi: Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays): the matrices, `visibleSourceRect` and `apply`.
- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): where the boxes come from.
- [Preview and capture](https://github.com/Anfet/yuv_camera/wiki/Preview-and-capture): `capture()` crops with the same geometry.
