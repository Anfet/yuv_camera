import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Describes where and how large a crop is, independently of the image it is applied to.
///
/// [place] resolves a target against an image size and returns an integer [Rect] inside the image. Targets work in
/// image pixels only: they know nothing about rotation, screen scale or widgets, so a frame returned by
/// `YuvCameraViewController.capture` can be used directly.
sealed class YuvCropTarget {
  const YuvCropTarget._();

  /// A box of exactly [size] pixels, placed by [alignment] inside the image and then shifted by [offset].
  ///
  /// A [size] larger than the image is scaled down to fit with its proportions kept. The box never leaves the image,
  /// so an [offset] that pushes it outside is clamped to the nearest edge.
  const factory YuvCropTarget.pixels(Size size, {Alignment alignment, Offset offset}) = _PixelsCropTarget;

  /// A box whose edges are given as fractions of the image: [left] and [right] of its width, [top] and [bottom] of
  /// its height.
  ///
  /// The defaults cover the whole image.
  const factory YuvCropTarget.fraction({double left, double top, double right, double bottom}) = _FractionCropTarget;

  /// A square whose side is [side] times the smaller image side (`(0, 1]`), placed like [YuvCropTarget.pixels].
  ///
  /// Combine it with an ellipse shape to cut a circle.
  const factory YuvCropTarget.square(double side, {Alignment alignment, Offset offset}) = _SquareCropTarget;

  /// Resolves this target for an image of [imageSize].
  ///
  /// The returned rectangle has integer edges and lies inside `Offset.zero & imageSize` (the size is rounded to whole
  /// pixels first). Throws an [ArgumentError] when the image or the target is invalid: an image side under one
  /// pixel, a non-positive [YuvCropTarget.pixels] size, a [YuvCropTarget.square] side outside `(0, 1]`, fraction edges
  /// that are not ordered inside `[0, 1]`, or a box that rounds to under one pixel.
  Rect place(Size imageSize) {
    if (!imageSize.width.isFinite || !imageSize.height.isFinite) {
      throw ArgumentError.value(imageSize, 'imageSize', 'must be finite');
    }
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width < 1 || height < 1) {
      throw ArgumentError.value(imageSize, 'imageSize', 'must be at least 1x1 pixel');
    }
    return _place(width, height);
  }

  Rect _place(int width, int height);

  static Rect _placeBox(int imageWidth, int imageHeight, int width, int height, Alignment alignment, Offset offset) {
    if (width > imageWidth || height > imageHeight) {
      // Scaling by the limiting side exactly: a floating-point ratio could floor one pixel short of the image side.
      if (imageWidth * height <= imageHeight * width) {
        height = math.max(1, height * imageWidth ~/ width);
        width = imageWidth;
      } else {
        width = math.max(1, width * imageHeight ~/ height);
        height = imageHeight;
      }
    }
    final dx = imageWidth - width;
    final dy = imageHeight - height;
    final left = ((alignment.x + 1) / 2 * dx + offset.dx).round().clamp(0, dx);
    final top = ((alignment.y + 1) / 2 * dy + offset.dy).round().clamp(0, dy);
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
}

class _PixelsCropTarget extends YuvCropTarget {
  const _PixelsCropTarget(this.size, {this.alignment = Alignment.center, this.offset = Offset.zero}) : super._();

  final Size size;
  final Alignment alignment;
  final Offset offset;

  @override
  Rect _place(int width, int height) {
    if (!(size.width > 0 && size.height > 0) || !size.isFinite || size.width.round() < 1 || size.height.round() < 1) {
      throw ArgumentError.value(size, 'size', 'must be positive');
    }
    return YuvCropTarget._placeBox(width, height, size.width.round(), size.height.round(), alignment, offset);
  }
}

class _SquareCropTarget extends YuvCropTarget {
  const _SquareCropTarget(this.side, {this.alignment = Alignment.center, this.offset = Offset.zero}) : super._();

  final double side;
  final Alignment alignment;
  final Offset offset;

  @override
  Rect _place(int width, int height) {
    if (!(side > 0 && side <= 1)) {
      throw ArgumentError.value(side, 'side', 'must be in (0, 1]');
    }
    final length = math.max(1, (side * math.min(width, height)).round());
    return YuvCropTarget._placeBox(width, height, length, length, alignment, offset);
  }
}

class _FractionCropTarget extends YuvCropTarget {
  const _FractionCropTarget({this.left = 0, this.top = 0, this.right = 1, this.bottom = 1}) : super._();

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  Rect _place(int width, int height) {
    if (!(0 <= left && left < right && right <= 1) || !(0 <= top && top < bottom && bottom <= 1)) {
      throw ArgumentError('fraction edges must satisfy 0 <= left < right <= 1 and 0 <= top < bottom <= 1: $left, $top, $right, $bottom');
    }
    final box = Rect.fromLTRB(
      (left * width).roundToDouble(),
      (top * height).roundToDouble(),
      (right * width).roundToDouble(),
      (bottom * height).roundToDouble(),
    );
    if (box.width < 1 || box.height < 1) {
      throw ArgumentError('fraction box rounds to under one pixel: $box');
    }
    return box;
  }
}
