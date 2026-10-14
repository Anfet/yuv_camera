# Preview and capture

**Task:** own the camera controller correctly (open, switch, dispose), show the preview, and capture the picture the
user actually sees.

**Conditions:** the packages and platform setup from
[Getting started](https://github.com/Anfet/yuv_camera/wiki/Getting-started), and an initialized `CameraController`. The
recipes below are widgets that take that controller, so you can put them in place of the `YuvCameraView` of the Getting
started page.

## Who owns what

| Object | Created by | Disposed by |
| --- | --- | --- |
| `CameraController` (from the `camera` plugin) | You: `CameraController(description, ResolutionPreset...)` then `await initialize()` | You. `YuvCameraView` never disposes it. |
| `YuvCameraView` | You, in your widget tree | The framework, when it leaves the tree. Its frame stream stops then. |
| `YuvCameraViewController` | You, and you pass it to the view | You: call `dispose()` when your widget is disposed. |
| The `YuvImage` returned by `capture()` | `yuv_camera`, as a new image | It is yours: nothing else holds it. |

When several screens share one camera, the owner of the controller is a `YuvCameraOrchestrator` instead of you; see
[Sharing the camera](https://github.com/Anfet/yuv_camera/wiki/Sharing-the-camera).

`YuvCameraView` requires an initialized controller. With an uninitialized one its frame source reports
`CameraController should be initialized`, and the view shows `Camera error:` followed by that error. Opening the
camera can fail: `availableCameras()` may return an empty list, and `initialize()` throws when the user denies the
permission. Catch both, and check `mounted` after every `await`, as the Getting started page does.

The `camera` plugin's own documentation describes how to react to the app moving to the background and back
([`camera` on pub.dev](https://pub.dev/packages/camera)). With your own controller, your app manages that lifecycle;
`YuvCameraLeaseBuilder` releases its lease while hidden and acquires one again when shown. For controller replacement:
if you pass a different `CameraController` to an existing `YuvCameraView`, it stops the old stream without calling
`onStreamStopped`, drops any frame and capture in flight, and starts the new one.

## `YuvCameraView` at a glance

| Parameter | Meaning |
| --- | --- |
| `cameraController` | Required. The initialized controller whose frames are shown. |
| `viewController` | A `YuvCameraViewController` for capture and the current geometry. |
| `fit`, `alignment` | How the frame fills the space. `fit` defaults to `YuvFrameFit.cover`, which crops the picture; use `contain` to see all of it. |
| `onFrame`, `onFrameInterval` | Your frame callback and its minimum interval (200 ms by default). See [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing). |
| `overlayBuilder` | Builds a widget over the preview from the geometry of the displayed frame. See [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays). |
| `onStreamStopped` | Called only after a stream error stops the stream; not on removal or controller replacement. |
| `onFramePresented` | Called for every frame that was confirmed as drawn; its argument says whether the shader path is in use. |

## Capture what is on screen

`viewController.capture()` returns the next frame that is actually drawn on screen, cropped to what is visible, as a new
`YuvImage` (or `null`). This recipe adds a capture button to a preview, shows the result and encodes it as PNG.

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Encodes [image] as PNG bytes.
Future<Uint8List> toPng(YuvImage image) async {
  final decoded = await image.toImage();
  try {
    final data = await decoded.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding returned no data.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    decoded.dispose();
  }
}

/// A preview with a capture button; [controller] must be initialized.
class CapturePanel extends StatefulWidget {
  const CapturePanel({super.key, required this.controller});

  final CameraController controller;

  @override
  State<CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends State<CapturePanel> {
  final YuvCameraViewController _view = YuvCameraViewController();
  YuvImage? _captured;
  String _status = 'Press the button to capture.';
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final image = await _view.capture();
      if (!mounted) return;
      if (image == null) {
        setState(() => _status = 'Nothing was captured: the view is not attached or stopped first.');
        return;
      }
      final png = await toPng(image);
      if (!mounted) return;
      setState(() {
        _captured = image;
        _status = 'Captured ${image.width}x${image.height}, PNG ${png.length} bytes.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Capture failed: $error');
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
          if (_captured case final image?)
            SizedBox(
              height: 120,
              width: double.infinity,
              child: YuvImageWidget(image: image, boxFit: BoxFit.contain),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _busy ? null : _capture, child: const Icon(Icons.camera)),
    );
  }
}
```

Expected result: pressing the button shows a line such as `Captured 480x640, PNG 312345 bytes.` (the size and byte count
depend on your camera and the picture) and a thumbnail of the captured picture under the preview.

What `capture()` does:

- It waits for the next frame that is really drawn, then returns it. It is not a snapshot of an older frame, and it is
  not a screenshot of your overlays: it contains camera pixels only.
- The image is cropped to the visible part of the frame and has the frame's rotation and mirror applied, so it matches
  what the preview shows. With the default `cover` fit that can be less than the whole camera frame.
- A second call while one is waiting returns the same pending result.
- It returns `null` when the view is not attached to the controller (for example before the view was built), or when the
  view stops before a frame is drawn: the widget is disposed, the camera controller is replaced, or the stream fails.
- An unexpected end of the camera stream is a stream error. The view stops and calls `onStreamStopped`; EOF is not a
  successful end of a live camera delivery.
- The returned image is a new image that you own, and you may mutate it. Its planes can keep the camera's row stride
  rather than being tightly packed; call `pack()` (see the
  [yuv_ffi wiki](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout#packed-or-preserved-layout)) if you need tight
  planes. To show or process it, use `YuvImageWidget` or the operations of `yuv_ffi`.

`viewController.geometry` is a `ValueListenable<YuvFrameGeometry?>` with the geometry of the displayed frame, `null`
until the first frame is drawn. It is the same object the `overlayBuilder` receives.

## Switch between cameras

Replace the controller only after the view that uses it has left the tree. This recipe removes the view, waits for the
frame that disposes it, disposes the old controller, and then opens the next camera.

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:yuv_camera/yuv_camera.dart';

/// A preview with a button that switches to the next available camera.
class SwitchableCamera extends StatefulWidget {
  const SwitchableCamera({super.key});

  @override
  State<SwitchableCamera> createState() => _SwitchableCameraState();
}

class _SwitchableCameraState extends State<SwitchableCamera> {
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  CameraController? _controller;
  Object? _problem;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _open(0);
  }

  Future<void> _open(int index) async {
    CameraController? created;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (!mounted) return;
      if (_cameras.isEmpty) {
        setState(() => _problem = 'No camera is available.');
        return;
      }
      created = CameraController(_cameras[index], ResolutionPreset.medium, enableAudio: false);
      await created.initialize();
      if (!mounted) {
        await created.dispose();
        return;
      }
      setState(() {
        _index = index;
        _controller = created;
        _problem = null;
      });
    } catch (error) {
      await created?.dispose();
      if (mounted) setState(() => _problem = error);
    }
  }

  Future<void> _switch() async {
    if (_switching || _cameras.length < 2) return;
    _switching = true;
    try {
      final old = _controller;
      setState(() => _controller = null); // removes the YuvCameraView, which stops its stream
      await WidgetsBinding.instance.endOfFrame; // the view is gone after this frame
      await old?.dispose();
      if (mounted) await _open((_index + 1) % _cameras.length);
    } finally {
      _switching = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_problem != null) return Scaffold(body: Center(child: Text('Camera unavailable: $_problem')));
    if (controller == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: YuvCameraView(cameraController: controller),
      floatingActionButton: FloatingActionButton(onPressed: _switch, child: const Icon(Icons.cameraswitch)),
    );
  }
}
```

Expected result: on a device with two cameras, pressing the button shows a spinner for a moment and then the other
camera; on a device with one camera nothing happens. This recipe was compiled and analyzed for Windows and Web; the
project has not run camera switching on a physical camera, so test it on your target devices.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| `capture()` returns `null` | The view was not attached yet, or it stopped before drawing a frame. Capture after the preview is visible, and do not dispose the controller or the page while waiting. |
| `capture()` returns an image smaller than the camera frame | Expected with `fit: YuvFrameFit.cover`: only the visible part is returned. Use `fit: YuvFrameFit.contain` to keep the whole frame. |
| The preview shows `Camera error: ...` | The frame stream failed or the controller was not initialized. `onStreamStopped` fires too. Open the camera again with a new controller; see [Platforms and troubleshooting](https://github.com/Anfet/yuv_camera/wiki/Platforms-and-troubleshooting). |
| An exception from `initialize()` | The permission was denied, no camera is available or it is in use. Catch it and show a message, as in Getting started. |
| The captured image does not look like the preview | Compare `fit`: capture follows the visible part and orientation, but not your overlays. |

## Related pages

- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing): handle frames before they are captured.
- [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays): the geometry behind the visible area.
- [yuv_ffi: Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): show or keep a captured `YuvImage`.
