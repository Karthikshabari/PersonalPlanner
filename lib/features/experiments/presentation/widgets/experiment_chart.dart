import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/experiment.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/experiment_chart_buckets.dart';
import '../../domain/experiment_dashboard.dart';
import 'experiment_ui.dart';

/// Height of the bars' area (ED30). The "Today" caption sits in the strip
/// below, which exists only while a bucket is today.
const experimentChartPlotHeight = 96.0;
const _todayStrip = 16.0;

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
    final styles = ExperimentStyles.of(context);
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
        final hasToday = data.buckets.any((b) => b.isToday);
        final narrow = width < experimentNarrowWidth - 2 * AppSpacing.lg;
        final unit = switch (data.grouping) {
          ExperimentChartGrouping.days => 'day',
          ExperimentChartGrouping.weeks => 'week',
          ExperimentChartGrouping.months => 'month',
        };
        final heading = 'Minutes per $unit';
        final caption = "Faint bar = that $unit's target";
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(heading, style: styles.label),
                Text(caption, style: styles.caption),
              ],
            ),
            if (data.groupingNote != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(data.groupingNote!, style: styles.caption),
            ],
            const SizedBox(height: AppSpacing.md),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: experimentChartSummary('$heading. $caption.', first, last),
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
                    size: Size(
                      width,
                      experimentChartPlotHeight + (hasToday ? _todayStrip : 0),
                    ),
                    painter: ExperimentChartPainter(
                      buckets: data.buckets,
                      selectedIndex: selected,
                      doneColor: styles.done,
                      targetColor: styles.scheme.onSurface.withValues(
                        alpha: 0.1,
                      ),
                      selectedColumnColor: styles.strip,
                      todayColor: styles.accentText,
                      todayLabelStyle: styles.caption.copyWith(
                        color: styles.accentText,
                      ),
                      gap: narrow ? 2 : 3,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Dates at the two ends of the chart.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_monthDay(first), style: styles.caption),
                Text(_monthDay(last), style: styles.caption),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Reserves one line of height while nothing is selected.
            Text(
              line ?? ' ',
              key: ValueKey('experiment-chart-line-$id'),
              style: styles.label,
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
    required this.targetColor,
    required this.selectedColumnColor,
    required this.todayColor,
    required this.todayLabelStyle,
    required this.gap,
  });

  final List<ExperimentChartBucket> buckets;
  final int? selectedIndex;
  final Color doneColor;
  final Color targetColor;
  final Color selectedColumnColor;
  final Color todayColor;
  final TextStyle todayLabelStyle;

  /// Space between two bars.
  final double gap;

  static const _barRadius = 3.0;
  static const _leaveBarHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final slot = size.width / buckets.length;
    final barWidth = math.max(1.0, slot - gap);
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
    final radius = Radius.circular(math.min(_barRadius, barWidth / 2));
    RRect bar(double left, double h) => RRect.fromRectAndRadius(
      Rect.fromLTWH(left, plot - h, barWidth, h),
      Radius.circular(math.min(radius.x, h / 2)),
    );

    final fill = Paint()..style = PaintingStyle.fill;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = todayColor;

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final left = slot * i + (slot - barWidth) / 2;

      if (i == selectedIndex) {
        canvas.drawRect(
          Rect.fromLTWH(slot * i, 0, slot, plot),
          fill..color = selectedColumnColor,
        );
      }

      // The faint target bar: every day, future ones included. A Leave or
      // Holiday day has no target, so it gets a thin sliver instead.
      final targetHeight = bucket.isLeaveOrHoliday
          ? _leaveBarHeight
          : heightOf(bucket.targetMin);
      if (targetHeight > 0) {
        canvas.drawRRect(bar(left, targetHeight), fill..color = targetColor);
      }

      // A completed amount is filled for every non-future bucket, also on a
      // Leave or Holiday day.
      var doneHeight = 0.0;
      if (!bucket.isFuture && bucket.doneMin > 0) {
        doneHeight = heightOf(bucket.doneMin);
        canvas.drawRRect(bar(left, doneHeight), fill..color = doneColor);
      }

      if (bucket.isToday) {
        final h = math.max(math.max(targetHeight, doneHeight), _leaveBarHeight);
        canvas.drawRRect(bar(left, h).inflate(0.5), outline);
        final label = TextPainter(
          text: TextSpan(text: 'Today', style: todayLabelStyle),
          textDirection: ui.TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final x = (slot * i + slot / 2 - label.width / 2)
            .clamp(0.0, math.max(0.0, size.width - label.width))
            .toDouble();
        label.paint(canvas, Offset(x, plot + 2));
        label.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(ExperimentChartPainter oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex ||
      doneColor != oldDelegate.doneColor ||
      targetColor != oldDelegate.targetColor ||
      selectedColumnColor != oldDelegate.selectedColumnColor ||
      todayColor != oldDelegate.todayColor ||
      todayLabelStyle != oldDelegate.todayLabelStyle ||
      gap != oldDelegate.gap ||
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
