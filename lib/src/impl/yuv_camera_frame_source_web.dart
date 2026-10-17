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
import 'package:yuv_camera/src/web_frame_copy.dart';
import 'package:yuv_camera/src/web_video_constraints.dart';
import 'package:yuv_camera/src/yuv_camera_frame.dart';
import 'package:yuv_camera/src/yuv_camera_frame_source.dart';

/// Web camera source backed by `MediaStreamTrackProcessor`, with a canvas
/// fallback for browsers that do not expose it.
final class YuvCameraFrameSourceImpl implements YuvCameraFrameSource {
  @visibleForTesting
  static void Function(web.MediaStreamTrack track)? onTrackStoppedForTesting;

  YuvCameraFrameSourceImpl(
    this.controller, {
    required this.onFrame,
    required this.onError,
    @visibleForTesting this.forceCanvasCallbackForTesting = false,
    @visibleForTesting this.forceVisibleRectMismatchForTesting = false,
    @visibleForTesting this.onBranchForTesting,
    @visibleForTesting this.onVideoFrameClosedForTesting,
    @visibleForTesting this.onRgbaPixelsForTesting,
    @visibleForTesting this.onCopyProbeForTesting,
    @visibleForTesting this.createReaderForTesting,
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
  final void Function(Object frame)? onVideoFrameClosedForTesting;
  @visibleForTesting
  final void Function(Uint8List rgba)? onRgbaPixelsForTesting;
  @visibleForTesting
  final void Function()? onCopyProbeForTesting;

  /// Replaces only reader acquisition; [track] remains owned by this source.
  @visibleForTesting
  final web.ReadableStreamDefaultReader Function(web.MediaStreamTrack track)? createReaderForTesting;
  final Stopwatch _clock = Stopwatch();
  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();
  web.MediaStream? _stream;
  web.MediaStreamTrack? _videoTrack;
  web.ReadableStreamDefaultReader? _reader;
  Future<void> _pendingTeardown = Future<void>.value();
  JSFunction? _endedListener;
  int? _videoFrameRequest;
  int _generation = 0;
  bool _running = false;
  bool _processing = false;
  bool _disposed = false;
  WebFrameCopyMode _copyMode = WebFrameCopyMode.canvas;
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
      onStarted: () => _startSession(generation).ignore(),
      onError: (error) => _fail(error, generation),
    );
  }

  Future<void> _startSession(int generation) async {
    final copyMode = await _probeCopyMode();
    if (_disposed || generation != _generation) return;
    _copyMode = copyMode;
    _clock
      ..reset()
      ..start();
    _running = true;
    if (!_startTrackProcessor(generation)) _scheduleNext();
  }

  Future<WebFrameCopyMode> _probeCopyMode() async {
    web.VideoFrame? probeFrame;
    try {
      onCopyProbeForTesting?.call();
      final probeCanvas = web.HTMLCanvasElement()
        ..width = 2
        ..height = 1;
      final context = probeCanvas.context2D;
      context
        ..fillStyle = 'rgb(13, 71, 203)'.toJS
        ..fillRect(0, 0, 1, 1)
        ..fillStyle = 'rgb(229, 41, 97)'.toJS
        ..fillRect(1, 0, 1, 1);
      final sample = Uint8List.fromList(context.getImageData(0, 0, 2, 1).data.toDart);
      final frame = web.VideoFrame(probeCanvas, web.VideoFrameInit(timestamp: 0));
      probeFrame = frame;
      return await probeWebFrameCopyForTesting(
        width: 2,
        height: 1,
        rgbaSample: sample,
        copyBgra: (buffer) => frame.copyTo(buffer, _bgraOptions).toDart,
        copyRgba: (buffer) => frame.copyTo(buffer, _rgbaOptions).toDart,
      );
    } catch (_) {
      // If the browser cannot create or read the sample frame, use canvas for this session.
      return WebFrameCopyMode.canvas;
    } finally {
      if (probeFrame != null) _closeVideoFrame(probeFrame);
    }
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
      final createReader = createReaderForTesting;
      final reader = createReader != null
          ? createReader(tracks.first)
          : web.ReadableStreamDefaultReader(web.MediaStreamTrackProcessor(web.MediaStreamTrackProcessorInit(track: tracks.first)).readable);
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
      if (_copyMode == WebFrameCopyMode.canvas ||
          forceVisibleRectMismatchForTesting ||
          videoFrame.format == null ||
          (visibleRect != null && (visibleRect.width != width || visibleRect.height != height))) {
        if (_copyMode == WebFrameCopyMode.canvas) onBranchForTesting?.call('copyCanvasFallback');
        if (forceVisibleRectMismatchForTesting) onBranchForTesting?.call('visibleRectMismatch');
        // Opaque frames expose no format that copyTo can read; other frames
        // may need display scaling that copyTo does not apply. Canvas renders
        // both at the same dimensions as the preview.
        _drawVideoFrame(videoFrame, width: width, height: height);
        return;
      }
      late final WebFrameCopyResult copied;
      try {
        copied = await copyVideoFrameBytesForTesting(
          width: width,
          height: height,
          useBgra: _copyMode == WebFrameCopyMode.bgra,
          copyBgra: (buffer) => videoFrame.copyTo(buffer, _bgraOptions).toDart,
          copyRgba: (buffer) => videoFrame.copyTo(buffer, _rgbaOptions).toDart,
          onRgbaFallback: () {
            if (_disposed || generation != _generation) return;
            _copyMode = WebFrameCopyMode.rgba;
            onBranchForTesting?.call('bgraRejected');
          },
        );
      } catch (_) {
        // A runtime copy or layout failure is recoverable through the canvas path.
        if (_disposed || generation != _generation) return;
        _copyMode = WebFrameCopyMode.canvas;
        onBranchForTesting?.call('copyCanvasFallback');
        _drawVideoFrame(videoFrame, width: width, height: height);
        return;
      }
      if (!copied.isBgra && generation == _generation && !_disposed) {
        _copyMode = WebFrameCopyMode.rgba;
        onRgbaPixelsForTesting?.call(copied.bytes);
      }
      if (generation == _generation && !_disposed) _deliverBgra(width, height, copied.bytes, copied.isBgra);
    } finally {
      _processing = false;
      _closeVideoFrame(videoFrame);
    }
  }

  void _drawVideoFrame(web.VideoFrame videoFrame, {required int width, required int height}) {
    _canvas
      ..width = width
      ..height = height;
    final context = _canvas.context2D;
    context.drawImage(videoFrame, 0, 0, width, height);
    final rgba = Uint8List.fromList(context.getImageData(0, 0, width, height).data.toDart);
    onRgbaPixelsForTesting?.call(rgba);
    _deliverBgra(width, height, rgba, false);
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
      final rgba = Uint8List.fromList(context.getImageData(0, 0, width, height).data.toDart);
      onRgbaPixelsForTesting?.call(rgba);
      _deliverBgra(width, height, rgba, false);
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
    if (reader != null) {
      // Attach the rejection handler now, even when the caller only uses stop().
      final cancellation = _cancelReader(reader);
      _pendingTeardown = Future.wait<void>([_pendingTeardown, cancellation]).then<void>((_) {});
    }
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
    stop();
    await _pendingTeardown;
  }

  Future<void> _cancelReader(web.ReadableStreamDefaultReader reader) async {
    try {
      await reader.cancel().toDart;
    } catch (_) {
      // An errored/closed reader may reject cancellation. Teardown still releases
      // its tracks; this expected race must not replace the original read error.
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
    onVideoFrameClosedForTesting?.call(frame);
  }

  void _release(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
      onTrackStoppedForTesting?.call(track);
    }
  }
}
