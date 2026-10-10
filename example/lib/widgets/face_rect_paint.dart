import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

class FaceRectPainter extends CustomPainter {
  final YuvFrameGeometry geometry;
  final Rect rect;
  final Color color;
  final double strokeWidth;

  FaceRectPainter({required this.geometry, required this.rect, this.color = Colors.green, this.strokeWidth = 2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRect(MatrixUtils.transformRect(geometry.uprightToView, rect), paint);
  }

  @override
  bool shouldRepaint(covariant FaceRectPainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth || oldDelegate.geometry != geometry;
  }
}
