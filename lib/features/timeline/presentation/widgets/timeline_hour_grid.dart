import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/planner_day_axis.dart';

/// Shared elapsed-time ruler and grid used by both Day and Week timelines.
/// The widget never converts a planner date through UTC; [date] is interpreted
/// by PlannerDayAxis in the configured planner timezone.
class TimelineHourGrid extends StatelessWidget {
  final DateTime date;
  final int gridMinutes;
  final double pixelsPerMinute;
  final double rulerWidth;
  final bool showRuler;

  const TimelineHourGrid({
    super.key,
    required this.date,
    this.gridMinutes = AppConstants.defaultGridMinutes,
    this.pixelsPerMinute = AppConstants.pixelsPerMinute,
    this.rulerWidth = AppConstants.hourLabelWidth,
    this.showRuler = true,
  });

  static double measuredRulerWidth(
    BuildContext context,
    DateTime date, {
    double? textScale,
  }) {
    final scale = textScale ?? MediaQuery.textScalerOf(context).scale(1);
    final textScaler = TextScaler.linear(scale);
    final style = Theme.of(context).textTheme.labelSmall;
    final labels = PlannerDayAxis(date).hourMarkers.map((m) => m.label);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: textScaler,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    return widest + AppSpacing.md * 2;
  }

  static bool equivalentMarkers(PlannerDayAxis left, PlannerDayAxis right) {
    final a = left.hourMarkers;
    final b = right.hourMarkers;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label ||
          a[i].elapsedMinutes != b[i].elapsedMinutes) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final axis = PlannerDayAxis(date);
    final tokens = AppThemeTokens.of(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _TimelineHourGridPainter(
            axis: axis,
            gridMinutes: gridMinutes,
            pixelsPerMinute: pixelsPerMinute,
            rulerWidth: showRuler ? rulerWidth : 0,
            showRuler: showRuler,
            labelStyle: labelStyle,
            lineColor: tokens.outline.withValues(alpha: 0.56),
            subdivisionColor: tokens.outline.withValues(alpha: 0.3),
            nonTimeColor: tokens.surfaceSubtle,
          ),
          child: const SizedBox.expand(),
        ),
        if (showRuler)
          for (final marker in axis.hourMarkers)
            if (marker.elapsedMinutes < axis.durationMinutes)
              Positioned(
                top: marker.elapsedMinutes * pixelsPerMinute + 2,
                left: AppSpacing.sm,
                width: math.max(0, rulerWidth - AppSpacing.md),
                child: Text(
                  marker.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
      ],
    );
  }
}

class _TimelineHourGridPainter extends CustomPainter {
  final PlannerDayAxis axis;
  final int gridMinutes;
  final double pixelsPerMinute;
  final double rulerWidth;
  final bool showRuler;
  final TextStyle? labelStyle;
  final Color lineColor;
  final Color subdivisionColor;
  final Color nonTimeColor;

  const _TimelineHourGridPainter({
    required this.axis,
    required this.gridMinutes,
    required this.pixelsPerMinute,
    required this.rulerWidth,
    required this.showRuler,
    required this.labelStyle,
    required this.lineColor,
    required this.subdivisionColor,
    required this.nonTimeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final timeWidth = math.max(0, size.width - rulerWidth).toDouble();
    final timeStart = Offset(rulerWidth, 0);
    final actualHeight = axis.durationMinutes * pixelsPerMinute;
    if (size.height > actualHeight) {
      canvas.drawRect(
        Rect.fromLTWH(0, actualHeight, size.width, size.height - actualHeight),
        Paint()..color = nonTimeColor,
      );
    }

    final majorPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final minorPaint = Paint()
      ..color = subdivisionColor
      ..strokeWidth = 0.5;
    final markers = axis.hourMarkers;
    for (var index = 0; index < markers.length; index++) {
      final marker = markers[index];
      final y = marker.elapsedMinutes * pixelsPerMinute;
      canvas.drawLine(
        Offset(timeStart.dx, y),
        Offset(timeStart.dx + timeWidth, y),
        majorPaint,
      );
      if (index >= markers.length - 1) continue;
      final next = markers[index + 1].elapsedMinutes;
      for (
        var minute = gridMinutes.toDouble();
        minute < next - marker.elapsedMinutes;
        minute += gridMinutes
      ) {
        final subdivisionY = (marker.elapsedMinutes + minute) * pixelsPerMinute;
        canvas.drawLine(
          Offset(timeStart.dx, subdivisionY),
          Offset(timeStart.dx + timeWidth, subdivisionY),
          minorPaint,
        );
      }
    }
    if (showRuler && rulerWidth > 0) {
      canvas.drawLine(
        Offset(rulerWidth, 0),
        Offset(rulerWidth, math.min(size.height, actualHeight)),
        majorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineHourGridPainter oldDelegate) =>
      axis.date != oldDelegate.axis.date ||
      axis.durationMinutes != oldDelegate.axis.durationMinutes ||
      gridMinutes != oldDelegate.gridMinutes ||
      pixelsPerMinute != oldDelegate.pixelsPerMinute ||
      rulerWidth != oldDelegate.rulerWidth ||
      showRuler != oldDelegate.showRuler ||
      labelStyle != oldDelegate.labelStyle ||
      lineColor != oldDelegate.lineColor ||
      subdivisionColor != oldDelegate.subdivisionColor ||
      nonTimeColor != oldDelegate.nonTimeColor;
}
