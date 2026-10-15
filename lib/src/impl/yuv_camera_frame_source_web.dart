import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_camera/src/camera_orientation.dart';
import 'package:yuv_camera/src/frame_read_loop.dart';
import 'package:yuv_camera/src/stream_start.dart';
import 'package:yuv_camera/src/web_video_constraints.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

/// Web camera source backed by `MediaStreamTrackProcessor`, with a canvas
/// fallback for browsers that do not expose it.
final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  YuvCameraFrameSourceImpl(this.controller, {
    required this.onFrame,
    required this.onError,
    @visibleForTesting this.forceCanvasCallbackForTesting = false,
    @visibleForTesting this.forceVisibleRectMismatchForTesting = false,
    @visibleForTesting this.onBranchForTesting,
    @visibleForTesting this.onVideoFrameClosedForTesting,
  });

  final CameraController controller;
  final void Function(YuvCameraFrame frame) onFrame;
  final void Function(Object error) onError;
  @visibleForTesting
  final bool forceCanvasCallbackForTesting;
  @visibleForTesting
  final bool forceVisibleRectMismatchForTesting;
  @visibleForTesting
  final void Function(String branch)? onBranchForTesting;
  @visibleForTesting
  final void Function()? onVideoFrameClosedForTesting;
  final Stopwatch _clock = Stopwatch();
  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();
  web.MediaStream? _stream;
  web.MediaStreamTrack? _videoTrack;
  web.ReadableStreamDefaultReader? _reader;
  JSFunction? _endedListener;
  int? _videoFrameRequest;
  int _generation = 0;
  bool _running = false;
  bool _processing = false;
  bool _disposed = false;
  bool _useBgra = true;
  late final web.VideoFrameCopyToOptions _bgraOptions = web.VideoFrameCopyToOptions(format: 'BGRA');
  late final web.VideoFrameCopyToOptions _rgbaOptions = web.VideoFrameCopyToOptions(format: 'RGBA');

  /// The active source track, for verifying browser device selection.
  @visibleForTesting
  web.MediaStreamTrack? get videoTrackForTesting => _stream?.getVideoTracks().toDart.firstOrNull;

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
        final devices = await web.window.navigator.mediaDevices.enumerateDevices().toDart;
        final videoInputs = [
          for (final device in devices.toDart)
            if (device.kind == 'videoinput' && device.deviceId.isNotEmpty) (deviceId: device.deviceId, label: device.label),
        ];
        final video = webVideoConstraints(
          videoInputs: videoInputs,
          description: controller.description,
          resolution: controller.resolutionPreset,
          fps: controller.mediaSettings.fps,
        );
        final constraints = web.MediaStreamConstraints(audio: false.toJS, video: video.jsify() as JSAny);
        return (await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart);
      },
      isCurrent: () => !_disposed && generation == _generation,
      release: _release,
      attach: (stream) async {
        _stream = stream;
        _video.srcObject = stream;
        _videoTrack = stream.getVideoTracks().toDart.firstOrNull;
        final listener = ((web.Event _) => _fail(StateError('Camera video track ended unexpectedly'), generation)).toJS;
        _endedListener = listener;
        _videoTrack?.addEventListener('ended', listener);
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
    if (forceCanvasCallbackForTesting) {
      onBranchForTesting?.call('processorUnavailable');
      return false;
    }
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
      final visibleRect = videoFrame.visibleRect;
      if (forceVisibleRectMismatchForTesting || videoFrame.format == null || (visibleRect != null && (visibleRect.width != width || visibleRect.height != height))) {
        if (forceVisibleRectMismatchForTesting) onBranchForTesting?.call('visibleRectMismatch');
        // Opaque frames expose no format that copyTo can read; other frames
        // may need display scaling that copyTo does not apply. Canvas renders
        // both at the same dimensions as the preview.
        _canvas
          ..width = width
          ..height = height;
        final context = _canvas.context2D;
        context.drawImage(videoFrame, 0, 0, width, height);
        _deliverBgra(width, height, Uint8List.fromList(context.getImageData(0, 0, width, height).data.toDart), false);
        return;
      }
      final copied = await copyVideoFrameBytesForTesting(
        width: width,
        height: height,
        useBgra: _useBgra,
        copyBgra: (buffer) async { await videoFrame.copyTo(buffer, _bgraOptions).toDart; },
        copyRgba: (buffer) async { await videoFrame.copyTo(buffer, _rgbaOptions).toDart; },
        onRgbaFallback: () => onBranchForTesting?.call('bgraRejected'),
      );
      if (!copied.isBgra) _useBgra = false;
      if (generation == _generation && !_disposed) _deliverBgra(width, height, copied.bytes, copied.isBgra);
    } finally {
      _processing = false;
      _closeVideoFrame(videoFrame);
    }
  }

  void _scheduleNext() {
    if (!_running) return;
    _videoFrameRequest = _video.requestVideoFrameCallback(
      ((num _, web.VideoFrameMetadata _) {
        if (forceCanvasCallbackForTesting) onBranchForTesting?.call('canvasCallback');
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
    final track = _videoTrack;
    _videoTrack = null;
    final endedListener = _endedListener;
    _endedListener = null;
    if (track != null && endedListener != null) track.removeEventListener('ended', endedListener);
    if (stream != null) _release(stream);
    _video.srcObject = null;
  }

  Future<void> stopAndWait() async {
    final reader = _reader;
    stop();
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {
        // Cancelling an already closed browser reader is an expected teardown race.
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  void _closeVideoFrame(web.VideoFrame frame) {
    frame.close();
    onVideoFrameClosedForTesting?.call();
  }

  void _release(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }
}

/// Copies frame bytes and falls back to RGBA when the browser rejects BGRA.
@visibleForTesting
Future<({Uint8List bytes, bool isBgra})> copyVideoFrameBytesForTesting({
  required int width,
  required int height,
  required bool useBgra,
  required Future<void> Function(web.AllowSharedBufferSource buffer) copyBgra,
  required Future<void> Function(web.AllowSharedBufferSource buffer) copyRgba,
  void Function()? onRgbaFallback,
}) async {
  // dart2wasm copies `Uint8List.toJS`; return the JS array the browser wrote.
  final buffer = Uint8List(width * height * 4).toJS;
  var isBgra = useBgra;
  try {
    await (isBgra ? copyBgra : copyRgba)(buffer);
  } catch (_) {
    // Browsers that reject BGRA can still write RGBA, which is converted on import.
    if (!isBgra) rethrow;
    onRgbaFallback?.call();
    isBgra = false;
    await copyRgba(buffer);
  }
  return (bytes: buffer.toDart, isBgra: isBgra);
}
