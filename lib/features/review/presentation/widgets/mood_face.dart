import 'package:flutter/material.dart';

import 'review_theme.dart';

/// Draws the face for mood [level] on a 24 × 24 grid scaled to the canvas.
/// Each level differs in shape so meaning never depends on colour alone.
class MoodFacePainter extends CustomPainter {
  MoodFacePainter({required this.level, required this.color});

  final int level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(12, 12), 9, stroke);
    if (level == 4) {
      canvas.drawPath(
        Path()
          ..moveTo(7.4, 10.6)
          ..quadraticBezierTo(9, 8.2, 10.6, 10.6),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(13.4, 10.6)
          ..quadraticBezierTo(15, 8.2, 16.6, 10.6),
        stroke,
      );
    } else {
      final fill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      for (final eye in const [Offset(9, 9.6), Offset(15, 9.6)]) {
        // The prototype's SVG dot also inherits the 1.6 stroke (D28).
        canvas.drawCircle(eye, 0.75, fill);
        canvas.drawCircle(eye, 0.75, stroke);
      }
    }
    final mouth = switch (level) {
      1 =>
        Path()
          ..moveTo(8, 13.6)
          ..quadraticBezierTo(12, 16.2, 16, 13.6),
      2 =>
        Path()
          ..moveTo(7.6, 13)
          ..quadraticBezierTo(12, 17.2, 16.4, 13),
      _ =>
        Path()
          ..moveTo(7, 12.6)
          ..quadraticBezierTo(12, 19.4, 17, 12.6),
    };
    canvas.drawPath(mouth, stroke);
    if (level >= 3) {
      final sparkle = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        const Offset(19.2, 4.2),
        const Offset(19.2, 6.4),
        sparkle,
      );
      canvas.drawLine(
        const Offset(18.1, 5.3),
        const Offset(20.3, 5.3),
        sparkle,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MoodFacePainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}

class MoodFace extends StatelessWidget {
  const MoodFace({super.key, required this.level, this.size = 24, this.color});

  final int level;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: MoodFacePainter(
        level: level,
        color: color ?? ReviewColors.of(context).mood(level),
      ),
    ),
  );
}
