import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dashed stadium (or circle) outline, used by the "Not reviewed" chip.
class DashedOutlinePainter extends CustomPainter {
  const DashedOutlinePainter({
    required this.color,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 3,
    this.circle = false,
    this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;
  final bool circle;

  /// Corner radius of the rounded outline; a full stadium when null.
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = circle
        ? (Path()..addOval(rect))
        : (Path()..addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(radius ?? size.height / 2),
            ),
          ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutlinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap ||
      oldDelegate.circle != circle ||
      oldDelegate.radius != radius;
}
