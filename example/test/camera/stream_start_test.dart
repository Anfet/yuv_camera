import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/src/stream_start.dart';

/// Models the web preview state `runStreamStart` touches: the generation,
/// the attached stream (`_mediaStream`), the started loop and `_lastError`.
/// A stream is a name; opens and attaches wait on test-controlled completers.
class _WebPreviewModel {
  int generation = 0;
  bool disposed = false;
  String? attached;
  final List<String> released = [];
  final List<String> started = [];
  Object? lastError;

  final List<Completer<String>> opens = [];
  final List<Completer<void>> plays = [];

  Future<void> start() {
    final captured = generation;
    return runStreamStart<String>(
      open: () {
        final open = Completer<String>();
        opens.add(open);
        return open.future;
      },
      isCurrent: () => !disposed && captured == generation,
      release: released.add,
      attach: (stream) {
        attached = stream;
        final play = Completer<void>();
        plays.add(play);
        return play.future;
      },
      onStarted: () => started.add(attached ?? 'no stream'),
      onError: (error) {
        stop();
        lastError = error;
      },
    );
  }

  /// `_stopLoop` + `_stopMediaTracks`: the attached stream is stopped by
  /// whoever stops the preview.
  void stop() {
    generation++;
    final stream = attached;
    if (stream != null) {
      released.add(stream);
      attached = null;
    }
  }

  void dispose() {
    stop();
    disposed = true;
  }

  Future<void> restart() {
    stop();
    return start();
  }
}

void main() {
  test('a preview disposed while getUserMedia waits releases the stream it gets and never starts', () async {
    final preview = _WebPreviewModel();
    final start = preview.start();
    preview.dispose();

    preview.opens.single.complete('camera-1');
    await start;
    expect(preview.released, ['camera-1'], reason: 'the camera must not stay on after the preview is gone');
    expect(preview.attached, isNull);
    expect(preview.plays, isEmpty);
    expect(preview.started, isEmpty);
  });

  test('two starts pending at once: only the latest one attaches and starts', () async {
    final preview = _WebPreviewModel();
    final first = preview.start();
    final second = preview.restart();

    preview.opens[1].complete('camera-2');
    await pumpEventQueue();
    preview.plays.single.complete();
    await second;
    preview.opens[0].complete('camera-1');
    await first;

    expect(preview.started, ['camera-2']);
    expect(preview.attached, 'camera-2');
    expect(preview.released, ['camera-1'], reason: 'the stream of the replaced start is released, not attached over the new one');
  });

  test('a getUserMedia error of a replaced start does not replace the new preview with an error', () async {
    final preview = _WebPreviewModel();
    final first = preview.start();
    final second = preview.restart();

    preview.opens[0].completeError(StateError('NotAllowedError'));
    await first;
    expect(preview.lastError, isNull);

    preview.opens[1].complete('camera-2');
    await pumpEventQueue();
    preview.plays.single.complete();
    await second;
    expect(preview.started, ['camera-2']);
    expect(preview.lastError, isNull);
  });

  test('a preview stopped while play() waits does not start, and the play error that follows is not reported', () async {
    final preview = _WebPreviewModel();
    final start = preview.start();
    preview.opens.single.complete('camera-1');
    await pumpEventQueue();
    expect(preview.attached, 'camera-1');

    preview.dispose();
    expect(preview.released, ['camera-1'], reason: 'the attached stream is stopped by dispose');
    preview.plays.single.completeError(StateError('AbortError: srcObject removed'));
    await start;
    expect(preview.started, isEmpty);
    expect(preview.lastError, isNull);
  });

  test('a start replaced while play() waits does not start its loop once play() succeeds', () async {
    final preview = _WebPreviewModel();
    final first = preview.start();
    preview.opens.single.complete('camera-1');
    await pumpEventQueue();

    final second = preview.restart();
    expect(preview.released, ['camera-1']);
    preview.plays.single.complete();
    await first;
    expect(preview.started, isEmpty, reason: 'the old start must not start a loop for the new stream');

    preview.opens[1].complete('camera-2');
    await pumpEventQueue();
    preview.plays[1].complete();
    await second;
    expect(preview.started, ['camera-2']);
  });

  test('an error of the current start is reported and the attached stream is stopped', () async {
    final preview = _WebPreviewModel();
    final start = preview.start();
    preview.opens.single.complete('camera-1');
    await pumpEventQueue();
    preview.plays.single.completeError(StateError('NotReadableError'));
    await start;

    expect(preview.lastError, isStateError);
    expect(preview.released, ['camera-1']);
    expect(preview.started, isEmpty);
  });

  test('a permission error of the current start is reported', () async {
    final preview = _WebPreviewModel();
    final start = preview.start();
    preview.opens.single.completeError(StateError('NotAllowedError'));
    await start;
    expect(preview.lastError, isStateError);
    expect(preview.released, isEmpty);
  });

  test('the current start attaches and starts once', () async {
    final preview = _WebPreviewModel();
    final start = preview.start();
    preview.opens.single.complete('camera-1');
    await pumpEventQueue();
    preview.plays.single.complete();
    await start;
    expect(preview.started, ['camera-1']);
    expect(preview.released, isEmpty);
    expect(preview.lastError, isNull);
  });
}
