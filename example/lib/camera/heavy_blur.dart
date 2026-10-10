import 'dart:typed_data';

import 'package:yuv_ffi/yuv_ffi.dart';

/// Blurs packed BGRA bytes outside the UI isolate for the device-check load.
Future<Uint8List> blurBgra(({List<int> bytes, int width, int height}) input) async {
  await YuvFfi.initialize();
  final image = YuvImage.bgra(input.width, input.height);
  image.yPlane.assignFrom(Uint8List.fromList(input.bytes));
  image.markDirty();
  image.applyGaussianBlur(radius: 10, sigma: 10);
  return image.toBgraBytes();
}
