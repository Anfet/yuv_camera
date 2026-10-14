import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/frame_read_loop.dart';

void main() {
  group('runFrameReadLoop', () {
    test('a frame of a read pending across stop and restart is closed, not transformed or shown', () async {
      final host = _PreviewHost();
      final oldReader = _FakeReader();
      host.start(oldReader);
      await pumpEventQueue();
      expect(oldReader.pendingReads, 1);

      host.stopAndRestart();
      final newReader = _FakeReader();
      host.start(newReader);
      await pumpEventQueue();

      final staleFrame = _FakeFrame('old');
      oldReader.resolveFrame(staleFrame);
      await pumpEventQueue();

      expect(staleFrame.isClosed, isTrue);
      expect(host.handedOn, isEmpty, reason: 'a stale frame goes to close, not to processing');
      expect(host.transformed, isEmpty);
      expect(host.shown, isEmpty);
      expect(host.lastError, isNull);
      expect(oldReader.readCount, 1, reason: 'the old loop must end instead of reading again');

      final freshFrame = _FakeFrame('new');
      newReader.resolveFrame(freshFrame);
      await pumpEventQueue();

      expect(host.transformed, ['new']);
      expect(host.shown, ['new']);
      expect(freshFrame.isClosed, isTrue);
      expect(newReader.readCount, 2, reason: 'the new loop keeps reading');
    });

    test('an error of a read pending across stop and restart does not reach the new stream', () async {
      final host = _PreviewHost();
      final oldReader = _FakeReader();
      host.start(oldReader);
      await pumpEventQueue();

      host.stopAndRestart();
      final newReader = _FakeReader();
      host.start(newReader);
      await pumpEventQueue();

      oldReader.resolveError(StateError('reader cancelled'));
      await pumpEventQueue();

      expect(host.lastError, isNull);
      expect(host.transformed, isEmpty);

      newReader.resolveFrame(_FakeFrame('new'));
      await pumpEventQueue();

      expect(host.shown, ['new']);
      expect(host.lastError, isNull);
    });

    test('a frame still in processing across stop and restart is not shown and the old loop stops reading', () async {
      final host = _PreviewHost()..holdCopy = true;
      final oldReader = _FakeReader();
      host.start(oldReader);
      await pumpEventQueue();

      final staleFrame = _FakeFrame('old');
      oldReader.resolveFrame(staleFrame);
      await pumpEventQueue();
      expect(host.pendingCopies, 1);

      host.stopAndRestart();
      final newReader = _FakeReader();
      host.start(newReader);
      await pumpEventQueue();

      host.completeCopy();
      await pumpEventQueue();

      expect(staleFrame.isClosed, isTrue);
      expect(host.transformed, isEmpty);
      expect(host.shown, isEmpty);
      expect(oldReader.readCount, 1);
    });

    test('an error thrown while processing a frame of a stopped stream is not reported', () async {
      final host = _PreviewHost()..holdCopy = true;
      final oldReader = _FakeReader();
      host.start(oldReader);
      await pumpEventQueue();
      oldReader.resolveFrame(_FakeFrame('old'));
      await pumpEventQueue();

      host.stopAndRestart();
      host.start(_FakeReader());
      host.failCopy(StateError('frame closed'));
      await pumpEventQueue();

      expect(host.lastError, isNull);
      expect(host.shown, isEmpty);
    });

    test('the current stream reports its errors and turns done into one terminal error', () async {
      final erroring = _PreviewHost();
      final erroringReader = _FakeReader();
      erroring.start(erroringReader);
      await pumpEventQueue();
      final error = StateError('camera unplugged');
      erroringReader.resolveError(error);
      await pumpEventQueue();
      expect(erroring.lastError, same(error));

      final ending = _PreviewHost();
      final endingReader = _FakeReader();
      ending.start(endingReader);
      await pumpEventQueue();
      endingReader.resolveFrame(_FakeFrame('a'));
      await pumpEventQueue();
      endingReader.resolveDone();
      await pumpEventQueue();
      expect(ending.shown, ['a']);
      expect(endingReader.readCount, 2);
      expect(ending.lastError, isA<StateError>());
      expect(ending.errorCount, 1);
    });

    test('done from a stale reader does not report a terminal error', () async {
      final host = _PreviewHost();
      final oldReader = _FakeReader();
      host.start(oldReader);
      await pumpEventQueue();

      host.stopAndRestart();
      oldReader.resolveDone();
      await pumpEventQueue();

      expect(host.lastError, isNull);
      expect(host.errorCount, 0);
    });
  });
}

class _FakeFrame {
  final String id;
  bool isClosed = false;

  _FakeFrame(this.id);
}

/// A reader whose reads stay pending until the test resolves them, like
/// `ReadableStreamDefaultReader.read()` waiting for the next camera frame.
class _FakeReader {
  final List<Completer<FrameReadResult<_FakeFrame>>> _reads = [];
  int readCount = 0;

  int get pendingReads => _reads.where((read) => !read.isCompleted).length;

  Future<FrameReadResult<_FakeFrame>> read() {
    readCount++;
    final completer = Completer<FrameReadResult<_FakeFrame>>();
    _reads.add(completer);
    return completer.future;
  }

  void resolveFrame(_FakeFrame frame) => _next.complete((done: false, frame: frame));

  void resolveDone() => _next.complete((done: true, frame: null));

  void resolveError(Object error) => _next.completeError(error);

  Completer<FrameReadResult<_FakeFrame>> get _next => _reads.firstWhere((read) => !read.isCompleted);
}

/// Models the state of the web preview that the read loop touches: the stream
/// generation bumped by `_stopLoop`, `_processVideoFrame` with its awaited
/// `copyTo`, `transform`, the presenter and `_lastError`.
class _PreviewHost {
  final List<String> handedOn = [];
  final List<String> transformed = [];
  final List<String> shown = [];
  Object? lastError;
  int errorCount = 0;
  bool holdCopy = false;

  int _generation = 0;
  bool _isProcessing = false;
  final List<Completer<void>> _copies = [];

  int get pendingCopies => _copies.where((copy) => !copy.isCompleted).length;

  void start(_FakeReader reader) {
    final generation = _generation;
    runFrameReadLoop<_FakeFrame>(
      read: reader.read,
      isCurrent: () => generation == _generation,
      onFrame: (frame) async {
        handedOn.add(frame.id);
        if (_isProcessing) {
          frame.isClosed = true;
          return;
        }
        await _process(frame, generation);
      },
      close: (frame) => frame.isClosed = true,
      onError: (error) {
        errorCount++;
        lastError = error;
      },
    ).ignore();
  }

  void stopAndRestart() => _generation++;

  void completeCopy() => _copies.firstWhere((copy) => !copy.isCompleted).complete();

  void failCopy(Object error) => _copies.firstWhere((copy) => !copy.isCompleted).completeError(error);

  Future<void> _process(_FakeFrame frame, int generation) async {
    _isProcessing = true;
    try {
      if (holdCopy) {
        final copy = Completer<void>();
        _copies.add(copy);
        await copy.future;
      }
      if (generation != _generation) {
        return;
      }
      transformed.add(frame.id);
      shown.add(frame.id);
    } finally {
      _isProcessing = false;
      frame.isClosed = true;
    }
  }
}
