import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/experiment.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/experiment_chart_buckets.dart';
import '../../domain/experiment_dashboard.dart';

/// Height of the bars' area (ED30). The today dot sits in the strip below.
const experimentChartPlotHeight = 140.0;
const _dotStrip = 10.0;

/// Minutes per day, week or month as one painted chart (R18). The whole chart
/// is a single [CustomPaint]; there is no widget per bar. Hover (desktop) and
/// tap (touch) select the bucket whose slot contains the pointer, which is the
/// nearest bar even when bars are only a few pixels wide (ED30, ED50).
class ExperimentChart extends StatefulWidget {
  const ExperimentChart({super.key, required this.view});

  final ExperimentView view;

  @override
  State<ExperimentChart> createState() => _ExperimentChartState();
}

class _ExperimentChartState extends State<ExperimentChart> {
  // The selection is remembered by the bucket's first date, so it survives a
  // regrouping only when the same bucket still starts on that date.
  String? _hoverFirstDate;
  String? _tappedFirstDate;

  ExperimentView? _dataView;
  double? _dataWidth;
  ExperimentChartData? _data;

  ExperimentChartData _dataFor(double width) {
    if (_data == null ||
        !identical(_dataView, widget.view) ||
        _dataWidth != width) {
      final view = widget.view;
      _data = buildExperimentChart(
        days: view.days,
        minutesByDay: view.minutesByDay,
        today: view.today,
        running: view.experiment.status == ExperimentStatus.running,
        width: width,
        formatDuration: formatMinutes,
      );
      _dataView = view;
      _dataWidth = width;
    }
    return _data!;
  }

  int? _indexOf(ExperimentChartData data, String? firstDate) {
    if (firstDate == null) return null;
    final index = data.buckets.indexWhere((b) => b.firstDate == firstDate);
    return index < 0 ? null : index;
  }

  int _bucketAt(ExperimentChartData data, double x, double width) {
    final slot = width / data.buckets.length;
    return (x / slot).floor().clamp(0, data.buckets.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final theme = Theme.of(context);
    final view = widget.view;
    final id = view.experiment.id;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final data = _dataFor(width);
        final hovered = _indexOf(data, _hoverFirstDate);
        final tapped = _indexOf(data, _tappedFirstDate);
        final selected = hovered ?? tapped;
        final line = selected == null ? null : data.buckets[selected].tapLine;
        final first = view.experiment.startDate;
        final last = view.experiment.endDate;
        final mutedStyle = theme.textTheme.bodySmall?.copyWith(
          color: tokens.textMuted,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.caption, style: mutedStyle),
            if (data.groupingNote != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(data.groupingNote!, style: mutedStyle),
            ],
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: experimentChartSummary(data.caption, first, last),
              child: MouseRegion(
                onHover: (event) => setState(() {
                  _hoverFirstDate = data
                      .buckets[_bucketAt(data, event.localPosition.dx, width)]
                      .firstDate;
                }),
                onExit: (_) => setState(() => _hoverFirstDate = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final tappedDate = data
                        .buckets[_bucketAt(
                          data,
                          details.localPosition.dx,
                          width,
                        )]
                        .firstDate;
                    setState(() {
                      _tappedFirstDate = _tappedFirstDate == tappedDate
                          ? null
                          : tappedDate;
                    });
                  },
                  child: CustomPaint(
                    key: ValueKey('experiment-chart-$id'),
                    size: Size(width, experimentChartPlotHeight + _dotStrip),
                    painter: ExperimentChartPainter(
                      buckets: data.buckets,
                      selectedIndex: selected,
                      doneColor: tokens.success,
                      belowTargetColor: tokens.textMuted.withValues(alpha: 0.6),
                      targetOutlineColor: tokens.outlineStrong,
                      futureOutlineColor: tokens.outline,
                      selectedColumnColor: tokens.surfaceSubtle,
                      todayDotColor: tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // A Wrap, not a Row: at large text sizes the two dates stack
            // instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.md,
              children: [
                Text(_monthDay(first), style: mutedStyle),
                Text(_monthDay(last), style: mutedStyle),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Reserves one line of height while nothing is selected.
            Text(
              line ?? ' ',
              key: ValueKey('experiment-chart-line-$id'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
      },
    );
  }

  static String _monthDay(String isoDate) =>
      DateFormat('MMM d').format(parseIsoDate(isoDate));
}

/// Paints every bucket of the chart in one pass (ED30) and describes each
/// bucket to screen readers (ED50).
class ExperimentChartPainter extends CustomPainter {
  ExperimentChartPainter({
    required this.buckets,
    required this.selectedIndex,
    required this.doneColor,
    required this.belowTargetColor,
    required this.targetOutlineColor,
    required this.futureOutlineColor,
    required this.selectedColumnColor,
    required this.todayDotColor,
  });

  final List<ExperimentChartBucket> buckets;
  final int? selectedIndex;
  final Color doneColor;
  final Color belowTargetColor;
  final Color targetOutlineColor;
  final Color futureOutlineColor;
  final Color selectedColumnColor;
  final Color todayDotColor;

  static const _barShare = 0.7;
  static const _leaveOutlineHeight = 3.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final slot = size.width / buckets.length;
    final barWidth = slot * _barShare;
    // The vertical scale is the largest of every done and target, at least 1.
    final scale = math.max(
      1,
      buckets.fold<int>(
        0,
        (m, b) => math.max(m, math.max(b.doneMin, b.targetMin)),
      ),
    );
    const plot = experimentChartPlotHeight;
    double heightOf(int minutes) =>
        minutes <= 0 ? 0 : math.max(1.0, minutes / scale * plot);

    final fill = Paint()..style = PaintingStyle.fill;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final left = slot * i + (slot - barWidth) / 2;

      if (i == selectedIndex) {
        canvas.drawRect(
          Rect.fromLTWH(slot * i, 0, slot, size.height),
          fill..color = selectedColumnColor,
        );
      }

      if (bucket.isLeaveOrHoliday) {
        _dashedRect(
          canvas,
          Rect.fromLTWH(
            left,
            plot - _leaveOutlineHeight,
            barWidth,
            _leaveOutlineHeight,
          ),
          outline..color = futureOutlineColor,
        );
      } else if (bucket.isFuture) {
        final h = heightOf(bucket.targetMin);
        if (h > 0) {
          _dashedRect(
            canvas,
            Rect.fromLTWH(left, plot - h, barWidth, h),
            outline..color = futureOutlineColor,
          );
        }
      } else {
        final h = heightOf(bucket.targetMin);
        if (h > 0) {
          _dashedRect(
            canvas,
            Rect.fromLTWH(left, plot - h, barWidth, h),
            outline..color = targetOutlineColor,
          );
        }
      }

      // A completed amount is filled for every non-future bucket, also on a
      // Leave or Holiday day (its target is 0, so it counts as met).
      if (!bucket.isFuture && bucket.doneMin > 0) {
        final h = heightOf(bucket.doneMin);
        final met = bucket.doneMin >= bucket.targetMin;
        canvas.drawRect(
          Rect.fromLTWH(left, plot - h, barWidth, h),
          fill..color = met ? doneColor : belowTargetColor,
        );
      }

      if (bucket.isToday) {
        canvas.drawCircle(
          Offset(slot * i + slot / 2, plot + _dotStrip / 2 + 1),
          2,
          fill..color = todayDotColor,
        );
      }
    }
  }

  /// Dashed outline of [rect], drawn along its path.
  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(ExperimentChartPainter oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex ||
      doneColor != oldDelegate.doneColor ||
      belowTargetColor != oldDelegate.belowTargetColor ||
      targetOutlineColor != oldDelegate.targetOutlineColor ||
      futureOutlineColor != oldDelegate.futureOutlineColor ||
      selectedColumnColor != oldDelegate.selectedColumnColor ||
      todayDotColor != oldDelegate.todayDotColor ||
      !listEquals(buckets, oldDelegate.buckets);

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    if (buckets.isEmpty) return const [];
    final slot = size.width / buckets.length;
    return [
      for (var i = 0; i < buckets.length; i++)
        CustomPainterSemantics(
          key: ValueKey(buckets[i].firstDate),
          rect: Rect.fromLTWH(slot * i, 0, slot, size.height),
          properties: SemanticsProperties(
            label: buckets[i].tapLine,
            textDirection: ui.TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(ExperimentChartPainter oldDelegate) =>
      !listEquals(buckets, oldDelegate.buckets);
}
