/// One result of a frame reader: either the stream has ended ([done]) or a
/// [frame] arrived. Mirrors `ReadableStreamDefaultReader.read()`.
typedef FrameReadResult<F> = ({bool done, F? frame});

/// Pulls frames from a single camera stream reader until it ends, fails, or
/// [isCurrent] reports that its source was stopped or replaced.
///
/// A frame that arrives for a stale source is passed to [close], never to
/// [onFrame]. Errors of stale sources are ignored.
Future<void> runFrameReadLoop<F extends Object>({
  required Future<FrameReadResult<F>> Function() read,
  required bool Function() isCurrent,
  required Future<void> Function(F frame) onFrame,
  required void Function(F frame) close,
  required void Function(Object error) onError,
}) async {
  while (isCurrent()) {
    try {
      final result = await read();
      final frame = result.frame;
      if (!isCurrent()) {
        if (frame != null) close(frame);
        return;
      }
      if (result.done) return;
      if (frame != null) await onFrame(frame);
    } catch (error) {
      if (isCurrent()) onError(error);
      return;
    }
  }
}
