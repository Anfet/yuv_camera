import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_orientation.dart';
import 'package:yuv_camera/src/frame_read_loop.dart';
import 'package:yuv_camera/src/stream_start.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

/// Web camera source backed by `MediaStreamTrackProcessor`, with a canvas
/// fallback for browsers that do not expose it.
final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  YuvCameraFrameSourceImpl(this.controller, {required this.onFrame, required this.onError});

  final CameraController controller;
  final void Function(YuvCameraFrame frame) onFrame;
  final void Function(Object error) onError;
  final Stopwatch _clock = Stopwatch();
  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();
  web.MediaStream? _stream;
  web.ReadableStreamDefaultReader? _reader;
  int? _videoFrameRequest;
  int _generation = 0;
  bool _running = false;
  bool _processing = false;
  bool _disposed = false;
  bool _useBgra = true;
  late final web.VideoFrameCopyToOptions _bgraOptions = web.VideoFrameCopyToOptions(format: 'BGRA');
  late final web.VideoFrameCopyToOptions _rgbaOptions = web.VideoFrameCopyToOptions(format: 'RGBA');

  @override
  Future<void> start() async {
    var generation = await Future<int>.value(_generation);
    if (_disposed || generation != _generation) return;
    stop();
    if (_disposed || !controller.value.isInitialized) {
      if (!_disposed) onError(StateError('CameraController should be initialized'));
      return;
    }
    generation = _generation;
    _video.setAttribute('playsinline', 'true');
    await runStreamStart<web.MediaStream>(
      open: () async {
        final constraints = web.MediaStreamConstraints(
          audio: false.toJS,
          video: ({'facingMode': _facingMode(controller.description.lensDirection)}.jsify() as JSAny),
        );
        return (await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart);
      },
      isCurrent: () => !_disposed && generation == _generation,
      release: _release,
      attach: (stream) async {
        _stream = stream;
        _video.srcObject = stream;
        await _video.play().toDart;
      },
      onStarted: () {
        _clock
          ..reset()
          ..start();
        _running = true;
        if (!_startTrackProcessor(generation)) _scheduleNext();
      },
      onError: (error) => _fail(error, generation),
    );
  }

  bool _startTrackProcessor(int generation) {
    final stream = _stream;
    if (stream == null) return false;
    final tracks = stream.getVideoTracks().toDart;
    if (tracks.isEmpty) return false;
    try {
      final processor = web.MediaStreamTrackProcessor(web.MediaStreamTrackProcessorInit(track: tracks.first));
      final reader = web.ReadableStreamDefaultReader(processor.readable);
      _reader = reader;
      _readLoop(reader, generation).ignore();
      return true;
    } catch (_) {
      // Not a failure: browsers without MediaStreamTrackProcessor (Firefox,
      // Safari) throw here, and the caller switches to the canvas path.
      _reader = null;
      return false;
    }
  }

  Future<void> _readLoop(web.ReadableStreamDefaultReader reader, int generation) => runFrameReadLoop<web.VideoFrame>(
    read: () async {
      final result = await reader.read().toDart;
      return (done: result.done, frame: result.value as web.VideoFrame?);
    },
    isCurrent: () => !_disposed && generation == _generation,
    onFrame: (frame) => _processVideoFrame(frame, generation),
    close: _closeVideoFrame,
    onError: (error) => _fail(error, generation),
  );

  Future<void> _processVideoFrame(web.VideoFrame videoFrame, int generation) async {
    if (_processing || !_running || generation != _generation) {
      _closeVideoFrame(videoFrame);
      return;
    }
    _processing = true;
    try {
      final width = videoFrame.displayWidth;
      final height = videoFrame.displayHeight;
      if (width <= 0 || height <= 0) return;
      // copyTo writes into the JS array; under dart2wasm `Uint8List.toJS` is a
      // copy, so the bytes are read back from the array it filled.
      final buffer = Uint8List(width * height * 4).toJS;
      var bgra = _useBgra;
      try {
        await videoFrame.copyTo(buffer, bgra ? _bgraOptions : _rgbaOptions).toDart;
      } catch (_) {
        // A browser that cannot convert to BGRA rejects the call; RGBA is then
        // converted on import, and every later frame skips the failing attempt.
        if (!bgra) rethrow;
        _useBgra = false;
        bgra = false;
        await videoFrame.copyTo(buffer, _rgbaOptions).toDart;
      }
      if (generation == _generation && !_disposed) _deliverBgra(width, height, buffer.toDart, bgra);
    } finally {
      _processing = false;
      _closeVideoFrame(videoFrame);
    }
  }

  void _scheduleNext() {
    if (!_running) return;
    _videoFrameRequest = _video.requestVideoFrameCallback(
      ((num _, web.VideoFrameMetadata _) {
        _captureCanvas();
        _scheduleNext();
      }).toJS,
    );
  }

  void _captureCanvas() {
    if (_processing || !_running) return;
    final width = _video.videoWidth;
    final height = _video.videoHeight;
    if (width <= 0 || height <= 0) return;
    _processing = true;
    try {
      _canvas
        ..width = width
        ..height = height;
      final context = _canvas.context2D;
      context.drawImage(_video, 0, 0, width, height);
      _deliverBgra(width, height, Uint8List.fromList(context.getImageData(0, 0, width, height).data.toDart), false);
    } catch (error) {
      _fail(error, _generation);
    } finally {
      _processing = false;
    }
  }

  void _deliverBgra(int width, int height, Uint8List bytes, bool isBgra) {
    onFrame(
      YuvCameraFrame(
        width: width,
        height: height,
        format: YuvPixelFormat.bgra8888,
        orientation: mirroredUnlessBackOrientation(controller.description.lensDirection),
        timestamp: _clock.elapsed,
        load: () {
          final image = YuvImage.bgra(width, height);
          if (isBgra) {
            image.yPlane.assignFrom(bytes);
            image.markDirty();
          } else {
            image.applyRgbaBytes(bytes);
          }
          return image;
        },
      ),
    );
  }

  void _fail(Object error, int generation) {
    if (_disposed || generation != _generation) return;
    stop();
    onError(error);
  }

  @override
  void stop() {
    _generation++;
    _running = false;
    _clock.stop();
    final reader = _reader;
    _reader = null;
    reader?.cancel();
    final videoFrameRequest = _videoFrameRequest;
    if (videoFrameRequest != null) _video.cancelVideoFrameCallback(videoFrameRequest);
    _videoFrameRequest = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) _release(stream);
    _video.srcObject = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  void _closeVideoFrame(web.VideoFrame frame) => frame.close();

  void _release(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  String _facingMode(CameraLensDirection direction) => switch (direction) {
    CameraLensDirection.front => 'user',
    CameraLensDirection.back || CameraLensDirection.external => 'environment',
  };
}
