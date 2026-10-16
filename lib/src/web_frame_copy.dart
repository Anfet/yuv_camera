import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:web/web.dart' as web;

enum WebFrameCopyMode { bgra, rgba, canvas }

typedef WebFrameCopy = Future<JSArray<web.PlaneLayout>> Function(web.AllowSharedBufferSource buffer);

typedef WebFrameCopyResult = ({Uint8List bytes, bool isBgra});

/// Checks the browser's copy formats against a known RGBA sample.
@visibleForTesting
Future<WebFrameCopyMode> probeWebFrameCopyForTesting({
  required int width,
  required int height,
  required Uint8List rgbaSample,
  required WebFrameCopy copyBgra,
  required WebFrameCopy copyRgba,
}) async {
  for (final attempt in <({WebFrameCopy copy, bool isBgra})>[(copy: copyBgra, isBgra: true), (copy: copyRgba, isBgra: false)]) {
    try {
      final copied = await _copyAndValidate(width: width, height: height, copy: attempt.copy, isBgra: attempt.isBgra);
      final expected = attempt.isBgra ? _rgbaToBgra(rgbaSample) : rgbaSample;
      if (listEquals(copied.bytes, expected)) return attempt.isBgra ? WebFrameCopyMode.bgra : WebFrameCopyMode.rgba;
    } catch (_) {
      // A failed capability probe intentionally selects the canvas fallback.
    }
  }
  return WebFrameCopyMode.canvas;
}

/// Copies one frame and rejects layouts the tight BGRA importer cannot read.
@visibleForTesting
Future<WebFrameCopyResult> copyVideoFrameBytesForTesting({
  required int width,
  required int height,
  required bool useBgra,
  required WebFrameCopy copyBgra,
  required WebFrameCopy copyRgba,
  void Function()? onRgbaFallback,
}) async {
  try {
    return await _copyAndValidate(width: width, height: height, copy: useBgra ? copyBgra : copyRgba, isBgra: useBgra);
  } on FormatException {
    rethrow;
  } catch (_) {
    if (!useBgra) rethrow;
    onRgbaFallback?.call();
    return _copyAndValidate(width: width, height: height, copy: copyRgba, isBgra: false);
  }
}

Future<WebFrameCopyResult> _copyAndValidate({required int width, required int height, required WebFrameCopy copy, required bool isBgra}) async {
  final buffer = Uint8List(width * height * 4).toJS;
  final layouts = (await copy(buffer)).toDart;
  if (layouts.length != 1 || layouts.single.offset != 0 || layouts.single.stride != width * 4) {
    throw const FormatException('VideoFrame.copyTo returned a non-tight RGBA layout');
  }
  return (bytes: buffer.toDart, isBgra: isBgra);
}

Uint8List _rgbaToBgra(Uint8List rgba) {
  final bgra = Uint8List.fromList(rgba);
  for (var offset = 0; offset + 3 < bgra.length; offset += 4) {
    final red = bgra[offset];
    bgra[offset] = bgra[offset + 2];
    bgra[offset + 2] = red;
  }
  return bgra;
}
