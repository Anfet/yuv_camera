import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_camera/yuv_camera.dart';

void main() {
  const image = Size(720, 960);

  test('places targets on a 720x960 image', () {
    final cases = <(YuvCropTarget, Rect)>[
      (const YuvCropTarget.fraction(left: .15, top: .15, right: .85, bottom: .75), const Rect.fromLTRB(108, 144, 612, 720)),
      (const YuvCropTarget.square(.5), const Rect.fromLTRB(180, 300, 540, 660)),
      (const YuvCropTarget.pixels(Size(1000, 500)), const Rect.fromLTRB(0, 300, 720, 660)),
      (const YuvCropTarget.pixels(Size(900, 1200)), const Rect.fromLTRB(0, 0, 720, 960)),
      (const YuvCropTarget.pixels(Size(200, 200), alignment: Alignment.topLeft, offset: Offset(650, 900)), const Rect.fromLTRB(520, 760, 720, 960)),
      (const YuvCropTarget.pixels(Size(200.4, 199.6), alignment: Alignment.topLeft), const Rect.fromLTRB(0, 0, 200, 200)),
      (const YuvCropTarget.square(1), const Rect.fromLTRB(0, 120, 720, 840)),
    ];
    for (final (target, expected) in cases) {
      expect(target.place(image), expected, reason: '$target');
    }
  });

  test('rejects an image under one pixel', () {
    expect(() => const YuvCropTarget.fraction().place(const Size(0.4, 960)), throwsArgumentError);
    expect(() => const YuvCropTarget.fraction().place(const Size(720, 0)), throwsArgumentError);
  });

  test('rejects a non-positive pixels size', () {
    expect(() => const YuvCropTarget.pixels(Size(0, 100)).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.pixels(Size(100, -1)).place(image), throwsArgumentError);
  });

  test('rejects a square side outside (0, 1]', () {
    expect(() => const YuvCropTarget.square(0).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.square(1.01).place(image), throwsArgumentError);
  });

  test('rejects a non-finite alignment or offset', () {
    expect(() => const YuvCropTarget.pixels(Size(100, 100), offset: Offset(double.nan, 0)).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.square(.5, offset: Offset(0, double.infinity)).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.square(.5, alignment: Alignment(double.nan, 0)).place(image), throwsArgumentError);
  });

  test('rejects fraction edges that are out of order or outside [0, 1]', () {
    expect(() => const YuvCropTarget.fraction(left: .5, right: .5).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.fraction(top: .6, bottom: .4).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.fraction(left: -.1).place(image), throwsArgumentError);
    expect(() => const YuvCropTarget.fraction(bottom: 1.1).place(image), throwsArgumentError);
  });

  test('rejects a fraction box that rounds to under one pixel', () {
    expect(() => const YuvCropTarget.fraction(left: .1, right: .1001).place(image), throwsArgumentError);
  });
}
