import 'package:flutter/material.dart';

import '../../domain/review_draft.dart';
import 'review_theme.dart';

/// Save review → (disabled while saving) → Saved with a drawn check on the
/// success colour. Any later edit returns the draft to idle, which shows
/// "Save review" again.
class ReviewSaveButton extends StatelessWidget {
  const ReviewSaveButton({
    super.key,
    required this.status,
    required this.enabled,
    required this.focusNode,
    required this.onPressed,
    this.buttonKey = const ValueKey('review-save'),
  });

  final ReviewSaveStatus status;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  /// Key of the button itself: `review-save` in Daily, `weekly-save` in
  /// Weekly (WD30).
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final saved = status == ReviewSaveStatus.saved;
    final saving = status == ReviewSaveStatus.saving;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final success = ReviewColors.of(context).success;
    final onSuccess =
        ThemeData.estimateBrightnessForColor(success) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return FilledButton(
      key: buttonKey,
      focusNode: focusNode,
      onPressed: enabled && !saving ? onPressed : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(150, 44),
        backgroundColor: saved ? success : null,
        foregroundColor: saved ? onSuccess : null,
        animationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saved) ...[
            TweenAnimationBuilder<double>(
              key: const ValueKey('review-save-check'),
              tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              builder: (context, progress, _) => CustomPaint(
                size: const Size.square(18),
                painter: _CheckPainter(progress, onSuccess),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(saved ? 'Saved' : 'Save review'),
        ],
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24;
    final path = Path()
      ..moveTo(5 * s, 12.5 * s)
      ..lineTo(9.5 * s, 17 * s)
      ..lineTo(19 * s, 7.5 * s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}
