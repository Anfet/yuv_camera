import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;
import 'package:yuv_camera/src/impl/yuv_camera_frame_source_web.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web reader cancellation is handled once and drained across generations', (tester) async {
    final unhandled = <Object?>[];
    final listener = ((web.PromiseRejectionEvent event) {
      unhandled.add(event.reason);
      event.preventDefault();
    }).toJS;
    web.window.addEventListener('unhandledrejection', listener);
    addTearDown(() => web.window.removeEventListener('unhandledrejection', listener));

    final cameras = await availableCameras();
    expect(cameras, isNotEmpty);
    final controller = CameraController(cameras.first, ResolutionPreset.low, enableAudio: false);
    addTearDown(controller.dispose);
    await controller.initialize();

    final closed = HashMap<Object, int>.identity();
    final tracks = <web.MediaStreamTrack>[];
    final stopped = <web.MediaStreamTrack>[];
    YuvCameraFrameSourceImpl.onTrackStoppedForTesting = stopped.add;
    addTearDown(() => YuvCameraFrameSourceImpl.onTrackStoppedForTesting = null);
    var deliveries = 0;

    // Read failure and track-ended race must keep the first error, even when
    // cancellation later rejects and no async teardown was requested initially.
    for (final readFailsFirst in [true, false]) {
      final reader = _ControlledReader();
      final errors = <Object>[];
      final source = YuvCameraFrameSourceImpl(
        controller,
        onFrame: (_) => deliveries++,
        onError: errors.add,
        createReaderForTesting: (track) {
          tracks.add(track);
          return reader.reader;
        },
        onVideoFrameClosedForTesting: (frame) => closed.update(frame, (count) => count + 1, ifAbsent: () => 1),
      );
      addTearDown(source.dispose);
      addTearDown(reader.finish);
      await source.start();
      await _waitFor(tester, () => reader.reads.isNotEmpty, 'pending read');
      final readError = web.DOMException('controlled read failure', 'NotReadableError');
      if (readFailsFirst) {
        reader.reads.single.reject(readError);
        await _waitFor(tester, () => errors.isNotEmpty, 'read error');
      }
      tracks.last.dispatchEvent(web.Event('ended'));
      if (!readFailsFirst) reader.reads.single.reject(readError);
      await _waitFor(tester, () => errors.isNotEmpty, 'track error');
      expect(errors, hasLength(1));
      expect(tracks.last.readyState, 'ended');
      if (readFailsFirst) expect(errors.single, same(readError));
      source.stop();
      source.stop();
      expect(reader.cancelCount, 1);
      if (readFailsFirst) {
        reader.cancellation.reject(web.DOMException('controlled cancel failure', 'InvalidStateError'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(unhandled, isEmpty, reason: 'synchronous stop alone must handle cancellation rejection');
      }
      var drained = false;
      final drain = source.stopAndWait().then((_) => drained = true);
      await tester.pump();
      if (!readFailsFirst) {
        expect(drained, isFalse, reason: 'stopAndWait must await the original cancellation');
        reader.cancellation.reject(web.DOMException('controlled cancel failure', 'InvalidStateError'));
      }
      await drain;
      source.dispose();
      source.dispose();
      await source.stopAndWait();
      await source.start();
      expect(reader.cancelCount, 1);
      expect(errors, hasLength(1));
      expect(tracks, hasLength(stopped.length));
    }

    // A new generation may run while an older cancel is still pending. A drain
    // after dispose must wait for both, regardless of their completion order.
    final readers = [_ControlledReader(), _ControlledReader()];
    final errors = <Object>[];
    var opened = 0;
    final source = YuvCameraFrameSourceImpl(
      controller,
      onFrame: (_) => deliveries++,
      onError: errors.add,
      createReaderForTesting: (track) {
        tracks.add(track);
        return readers[opened++].reader;
      },
      onVideoFrameClosedForTesting: (frame) => closed.update(frame, (count) => count + 1, ifAbsent: () => 1),
    );
    addTearDown(source.dispose);
    for (final reader in readers) {
      addTearDown(reader.finish);
    }
    await source.start();
    await _waitFor(tester, () => readers.first.reads.isNotEmpty, 'first generation');
    source.stop();
    source.stop();
    await source.start();
    await _waitFor(tester, () => readers.last.reads.isNotEmpty, 'restarted generation');
    final lateAfterStop = _frame();
    readers.first.reads.single.resolve(web.ReadableStreamReadResult(done: false, value: lateAfterStop));
    final liveFrame = _frame();
    readers.last.reads.first.resolve(web.ReadableStreamReadResult(done: false, value: liveFrame));
    await _waitFor(tester, () => deliveries == 1 && readers.last.reads.length == 2, 'restarted delivery');
    source.dispose();
    source.dispose();
    final lateAfterDispose = _frame();
    readers.last.reads.last.resolve(web.ReadableStreamReadResult(done: false, value: lateAfterDispose));
    var firstDrained = false;
    var secondDrained = false;
    final firstDrain = source.stopAndWait().then((_) => firstDrained = true);
    final secondDrain = source.stopAndWait().then((_) => secondDrained = true);
    readers.last.cancellation.resolve();
    await tester.pump();
    expect(firstDrained || secondDrained, isFalse, reason: 'previous generation still owns a pending cancel');
    readers.first.cancellation.resolve();
    await Future.wait([firstDrain, secondDrain]);
    await source.start();
    expect(opened, 2, reason: 'dispose is terminal');
    expect(readers.map((reader) => reader.cancelCount), [1, 1]);
    expect(errors, isEmpty);

    // Allow the browser's unhandledrejection task to run after both rejections.
    await tester.pump(const Duration(milliseconds: 100));
    expect(unhandled, isEmpty);
    expect(deliveries, 1, reason: 'no delivery from a stopped/disposed generation');
    for (final frame in [lateAfterStop, liveFrame, lateAfterDispose]) {
      expect(closed[frame], 1, reason: 'every received VideoFrame closes exactly once');
      expect(frame.codedWidth, 0, reason: 'the browser frame really closed');
    }
    expect(closed.values.every((count) => count == 1), isTrue);
    expect(tracks, hasLength(4));
    expect(stopped, orderedEquals(tracks));
    expect(tracks.every((track) => track.readyState == 'ended'), isTrue);
    binding.reportData = {
      'readAndCancelRejectionCases': 2,
      'readerCancellations': 4,
      'stoppedTracks': stopped.length,
      'receivedFramesClosedOnce': 3,
      'lateDeliveries': deliveries - 1,
      'unhandledRejections': unhandled.length,
    };
  }, timeout: const Timeout(Duration(seconds: 90)));
}

final class _ControlledReader {
  _ControlledReader() {
    final object = JSObject();
    object['read'] = (() {
      final read = _PendingPromise<web.ReadableStreamReadResult>();
      reads.add(read);
      return read.promise;
    }).toJS;
    object['cancel'] = (() {
      cancelCount++;
      return cancellation.promise;
    }).toJS;
    reader = object as web.ReadableStreamDefaultReader;
  }

  late final web.ReadableStreamDefaultReader reader;
  final reads = <_PendingPromise<web.ReadableStreamReadResult>>[];
  final cancellation = _PendingPromise<JSAny?>();
  int cancelCount = 0;

  void finish() {
    cancellation.resolve();
    for (final read in reads) {
      read.resolve(web.ReadableStreamReadResult(done: true));
    }
  }
}

final class _PendingPromise<T extends JSAny?> {
  _PendingPromise() {
    promise = JSPromise<T>(
      ((JSFunction resolve, JSFunction reject) {
        _resolve = resolve;
        _reject = reject;
      }).toJS,
    );
  }

  late final JSPromise<T> promise;
  late final JSFunction _resolve;
  late final JSFunction _reject;
  bool _completed = false;

  void resolve([T? value]) {
    if (_completed) return;
    _completed = true;
    _resolve.callAsFunction(null, value);
  }

  void reject(JSAny error) {
    if (_completed) return;
    _completed = true;
    _reject.callAsFunction(null, error);
  }
}

web.VideoFrame _frame() {
  final canvas = web.HTMLCanvasElement()
    ..width = 2
    ..height = 2;
  canvas.context2D.fillRect(0, 0, 2, 2);
  return web.VideoFrame(canvas, web.VideoFrameInit(timestamp: 0));
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition, String what) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $what');
}
