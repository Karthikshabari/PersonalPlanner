import 'package:flutter/material.dart';

import '../theme/app_theme_tokens.dart';
import '../../features/timeline/domain/timeline_geometry.dart';

/// Pure background layer for a scheduled task block.
///
/// The planned surface always covers the visible scheduled span.  Committed
/// actual time paints cumulatively from the original task start; unfinished
/// timer time is intentionally not part of this layer.
class TaskProgressBackground extends StatelessWidget {
  final TimelineTaskGeometry geometry;

  const TaskProgressBackground({super.key, required this.geometry});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return CustomPaint(
      painter: _TaskProgressPainterWithGeometry(
        geometry: geometry,
        planned: tokens.plannedTaskFill,
        actual: tokens.actualTaskFill,
        overtime: tokens.actualTaskFill.withValues(alpha: 0.72),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Internal painter with geometry values. It is kept separate so the public
/// widget remains a small decoration API and never exposes canvas details.
class _TaskProgressPainterWithGeometry extends CustomPainter {
  final TimelineTaskGeometry geometry;
  final Color planned;
  final Color actual;
  final Color overtime;

  const _TaskProgressPainterWithGeometry({
    required this.geometry,
    required this.planned,
    required this.actual,
    required this.overtime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = planned);
    final fraction = geometry.actualCoverageFraction;
    if (fraction > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * fraction),
        Paint()..color = actual,
      );
    }
    // Overtime is a full-task value, but its visual marker is painted once on
    // the segment containing the original scheduled end. Each segment's
    // semantics still exposes the same value through TaskBlockWidget.
    if (geometry.overtimeDuration > Duration.zero &&
        geometry.isScheduledEndSegment) {
      final markerHeight = size.height.clamp(2.0, 5.0);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - markerHeight, size.width, markerHeight),
        Paint()..color = overtime,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TaskProgressPainterWithGeometry oldDelegate) =>
      geometry != oldDelegate.geometry ||
      planned != oldDelegate.planned ||
      actual != oldDelegate.actual ||
      overtime != oldDelegate.overtime;
}
