/// Opens and attaches the camera stream for one start of a source, handing
/// results on only while that start is still current.
///
/// A stream whose start was superseded after [open] completes is handed to
/// [release]. Errors from superseded starts are ignored.
Future<void> runStreamStart<S extends Object>({
  required Future<S> Function() open,
  required bool Function() isCurrent,
  required void Function(S stream) release,
  required Future<void> Function(S stream) attach,
  required void Function() onStarted,
  required void Function(Object error) onError,
}) async {
  try {
    final stream = await open();
    if (!isCurrent()) {
      release(stream);
      return;
    }
    await attach(stream);
    if (isCurrent()) onStarted();
  } catch (error) {
    if (isCurrent()) onError(error);
  }
}
