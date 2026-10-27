import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../domain/analytics_models.dart';
import '../../domain/follow_through_target.dart';

class InsightsSectionCard extends StatelessWidget {
  const InsightsSectionCard({
    super.key,
    required this.title,
    this.headerTrailing,
    this.stackHeader = false,
    required this.child,
  });

  final String title;
  final Widget? headerTrailing;
  final bool stackHeader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (headerTrailing == null)
              Text(title, style: Theme.of(context).textTheme.headlineSmall)
            else if (!stackHeader)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  headerTrailing!,
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  headerTrailing!,
                ],
              ),
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      ),
    );
  }
}

class ConsistencyGrid extends StatelessWidget {
  const ConsistencyGrid({
    super.key,
    required this.snapshot,
    required this.compact,
  });

  final InsightsSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visibleRange = consistencyCalendarRange(
      snapshot.generatedFor,
      compact: compact,
    );
    final visibleStart = visibleRange.start;
    final visibleEndExclusive = visibleRange.endExclusive;
    final days = {
      for (final day in snapshot.consistencyDays)
        if (!day.date.isBefore(visibleStart) &&
            day.date.isBefore(visibleEndExclusive))
          isoDateString(day.date): day,
    };
    final firstWeek = startOfWeek(visibleStart);
    final lastWeek = startOfWeek(addDays(visibleEndExclusive, -1));
    final weekCount = _calendarDayDifference(firstWeek, lastWeek) ~/ 7 + 1;
    final allWeeks = List.generate(
      weekCount,
      (index) => addDays(firstWeek, index * 7),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 34.0;
        const gap = 3.0;
        final available = math.max(0.0, constraints.maxWidth - labelWidth);
        // The compact grid scrolls sideways, so it keeps the 9 px floor. The
        // wider grid does not scroll: it may shrink to 8 px and, if that is
        // still too wide, drops its oldest weeks rather than overflowing.
        final minCell = compact ? 9.0 : 8.0;
        var weeks = allWeeks;
        var fit = (available - (weekCount - 1) * gap) / weekCount;
        if (!compact && fit < minCell) {
          final fitting = ((available + gap) / (minCell + gap)).floor().clamp(
            1,
            weekCount,
          );
          weeks = allWeeks.sublist(weekCount - fitting);
          fit = (available - (fitting - 1) * gap) / fitting;
        }
        final cellSize = fit.clamp(minCell, 16.0);
        final shownStart = weeks.length == weekCount
            ? visibleStart
            : weeks.first;
        final gridWidth = weeks.length * cellSize + (weeks.length - 1) * gap;
        final calendarWidth = labelWidth + gridWidth;
        final tokens = AppThemeTokens.of(context);
        final calendar = SizedBox(
          width: calendarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month and weekday labels are visual; the grid below says the
              // same in its own labels.
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(left: labelWidth),
                  child: SizedBox(
                    width: gridWidth,
                    height: 20,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: _monthLabels(
                        context,
                        weeks,
                        shownStart,
                        visibleEndExclusive,
                        cellSize,
                        gap,
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: labelWidth,
                      child: Column(
                        children: [
                          for (final label
                              in plannerWeekStartDay == WeekStartDay.sunday
                                  ? const [
                                      'Sun',
                                      '',
                                      'Tue',
                                      '',
                                      'Thu',
                                      '',
                                      'Sat',
                                    ]
                                  : const [
                                      'Mon',
                                      '',
                                      'Wed',
                                      '',
                                      'Fri',
                                      '',
                                      'Sun',
                                    ])
                            SizedBox(
                              height: cellSize + gap,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: tokens.textMuted),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // One group for the whole grid; each week is one stop whose
                  // custom actions open that week's days.
                  Semantics(
                    container: true,
                    label: 'Consistency calendar, ${weeks.length} weeks',
                    child: SizedBox(
                      width: gridWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var weekIndex = 0;
                            weekIndex < weeks.length;
                            weekIndex++
                          ) ...[
                            if (weekIndex > 0) const SizedBox(width: gap),
                            _weekColumn(
                              context,
                              weeks[weekIndex],
                              days,
                              cellSize,
                              gap,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        // The compact grid opens on its newest weeks, so today is in view.
        final calendarViewport = compact
            ? SingleChildScrollView(
                key: const ValueKey('consistency-grid-scroll'),
                scrollDirection: Axis.horizontal,
                reverse: calendarWidth > constraints.maxWidth,
                child: calendar,
              )
            : calendar;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!snapshot.hasConsistencyHistory)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Start planning your days to build your consistency history.',
                ),
              ),
            calendarViewport,
            const SizedBox(height: AppSpacing.md),
            _legend(context, constraints.maxWidth),
          ],
        );
      },
    );
  }

  List<Widget> _monthLabels(
    BuildContext context,
    List<DateTime> weeks,
    DateTime visibleStart,
    DateTime visibleEndExclusive,
    double cellSize,
    double gap,
  ) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppThemeTokens.of(context).textMuted);
    final entries = <({double left, String text})>[];
    var lastMonth = -1;
    for (var index = 0; index < weeks.length; index++) {
      final representative = index == 0
          ? visibleStart
          : List.generate(
              7,
              (day) => addDays(weeks[index], day),
            ).firstWhere((date) => date.day == 1, orElse: () => weeks[index]);
      final containsMonthStart =
          index == 0 ||
          List.generate(7, (day) => addDays(weeks[index], day)).any(
            (date) =>
                date.day == 1 &&
                !date.isBefore(visibleStart) &&
                date.isBefore(visibleEndExclusive),
          );
      final monthKey = representative.year * 100 + representative.month;
      if (!containsMonthStart || monthKey == lastMonth) continue;
      lastMonth = monthKey;
      entries.add((
        left: index * (cellSize + gap),
        text: DateFormat('MMM').format(representative),
      ));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final labels = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      // A short first month sits one or two columns before the next label;
      // drop it when the two would run together ("OctNov").
      if (i + 1 < entries.length) {
        final painter = TextPainter(
          text: TextSpan(text: entry.text, style: style),
          textDirection: ui.TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        painter.dispose();
        if (entries[i + 1].left - entry.left < width + 4) continue;
      }
      labels.add(
        Positioned(
          left: entry.left,
          child: Text(entry.text, style: style),
        ),
      );
    }
    return labels;
  }

  ConsistencyDay _resolveDay(DateTime date, ConsistencyDay? day) =>
      day ??
      ConsistencyDay(
        date: date,
        plannedMinutes: 0,
        completedPlannedMinutes: 0,
        actualMinutes: 0,
        isFuture: date.isAfter(startOfDay(snapshot.generatedFor)),
      );

  /// One week of cells as a single screen-reader stop: it says how many days
  /// were a success and offers each day's details as a custom action.
  Widget _weekColumn(
    BuildContext context,
    DateTime weekStart,
    Map<String, ConsistencyDay> days,
    double cellSize,
    double gap,
  ) {
    final results = <ConsistencyDay, DayResult?>{};
    for (var weekday = 0; weekday < 7; weekday++) {
      final date = addDays(weekStart, weekday);
      final day = _resolveDay(date, days[isoDateString(date)]);
      results[day] = classifyDay(day, target: snapshot.followThroughTarget);
    }
    final successes = results.values
        .where((result) => result == DayResult.success)
        .length;
    return Semantics(
      container: true,
      label:
          'Week of ${DateFormat('MMM d, yyyy').format(weekStart)}: '
          '$successes successful ${successes == 1 ? 'day' : 'days'}',
      customSemanticsActions: {
        for (final entry in results.entries)
          CustomSemanticsAction(
            label: _dayTooltip(entry.key, entry.value),
          ): () =>
              _showDayDetails(context, entry.key, entry.value),
      },
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var weekday = 0; weekday < 7; weekday++) ...[
              _dayCell(
                context,
                addDays(weekStart, weekday),
                days[isoDateString(addDays(weekStart, weekday))],
                cellSize,
              ),
              if (weekday < 6) SizedBox(height: gap),
            ],
          ],
        ),
      ),
    );
  }

  /// What the shades, the neutral cell and the hatching mean, and the
  /// follow-through percent a day needs to be a Success.
  Widget _legend(BuildContext context, double maxWidth) {
    final tokens = AppThemeTokens.of(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: tokens.textMuted);
    Widget swatch(Color color, {bool outlined = false, bool hatched = false}) =>
        SizedBox(
          width: 12,
          height: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: outlined ? Border.all(color: tokens.outline) : null,
            ),
            child: hatched
                ? CustomPaint(painter: _BreakHatchPainter(tokens.outline))
                : null,
          ),
        );
    // Large text wraps inside an item instead of running past the card.
    Widget item(List<Widget> children) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            children[i] is Text ? Flexible(child: children[i]) : children[i],
          ],
        ],
      ),
    );
    return Column(
      key: const ValueKey('consistency-legend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            item([
              Text('Less', style: style),
              for (final intensity in const [
                ConsistencyIntensity.low,
                ConsistencyIntensity.medium,
                ConsistencyIntensity.high,
                ConsistencyIntensity.strong,
              ])
                swatch(_intensityColor(tokens, intensity)),
              Text('More', style: style),
            ]),
            item([
              swatch(_intensityColor(tokens, ConsistencyIntensity.neutral)),
              Text('Missed', style: style),
            ]),
            item([
              swatch(
                _intensityColor(tokens, ConsistencyIntensity.neutral),
                outlined: true,
              ),
              Text('No plan', style: style),
            ]),
            item([
              swatch(
                _intensityColor(tokens, ConsistencyIntensity.neutral),
                outlined: true,
                hatched: true,
              ),
              Text('Break', style: style),
            ]),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Success is ${followThroughTargetPercent(snapshot.followThroughTarget)}% '
          'of planned time done.',
          style: style,
        ),
      ],
    );
  }

  static Color _intensityColor(
    AppThemeTokens tokens,
    ConsistencyIntensity intensity,
  ) => switch (intensity) {
    ConsistencyIntensity.neutral => tokens.surfaceSubtle,
    ConsistencyIntensity.low => Color.alphaBlend(
      tokens.success.withValues(alpha: 0.18),
      tokens.surfaceRaised,
    ),
    ConsistencyIntensity.medium => Color.alphaBlend(
      tokens.success.withValues(alpha: 0.42),
      tokens.surfaceRaised,
    ),
    ConsistencyIntensity.high => Color.alphaBlend(
      tokens.success.withValues(alpha: 0.68),
      tokens.surfaceRaised,
    ),
    ConsistencyIntensity.strong => tokens.success,
  };

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    ConsistencyDay? day,
    double size,
  ) {
    final effectiveDay = _resolveDay(date, day);
    final tokens = AppThemeTokens.of(context);
    final result = classifyDay(
      effectiveDay,
      target: snapshot.followThroughTarget,
    );
    // Success keeps the follow-through shades; Started (and today once some
    // planned time is done) gets the lowest filled shade; Missed stays unfilled.
    final intensity = switch (result) {
      DayResult.success => effectiveDay.intensity,
      DayResult.started => ConsistencyIntensity.low,
      DayResult.missed ||
      DayResult.empty ||
      DayResult.breakDay => ConsistencyIntensity.neutral,
      null =>
        effectiveDay.completedPlannedMinutes > 0
            ? ConsistencyIntensity.low
            : ConsistencyIntensity.neutral,
    };
    final color = _intensityColor(tokens, intensity);
    final tooltip = _dayTooltip(effectiveDay, result);
    // The week column owns the screen-reader node, so the cell has none.
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: InkWell(
        key: ValueKey('consistency-day-${isoDateString(date)}'),
        borderRadius: BorderRadius.circular(3),
        onTap: () => _showDayDetails(context, effectiveDay, result),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            // Paint in the cell subtree. An Ink here would target the
            // outer Scaffold Material and be covered by the opaque card.
            key: ValueKey('consistency-cell-${isoDateString(date)}'),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: effectiveDay.isNeutral
                  ? Border.all(color: tokens.outline)
                  : null,
            ),
            // A break day is hatched so it reads apart from an empty day.
            child: effectiveDay.isBreak
                ? CustomPaint(
                    key: ValueKey('consistency-break-${isoDateString(date)}'),
                    painter: _BreakHatchPainter(tokens.outline),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _dayTooltip(ConsistencyDay day, DayResult? result) {
    if (day.isBreak) {
      return '${DateFormat('MMM d, yyyy').format(day.date)} · '
          'Break · ${day.breakLabel}';
    }
    final follow = day.followThroughPercent == null
        ? 'Neutral'
        : '${_resultLabel(day, result)} · ${day.followThroughPercent}% time done';
    return '${DateFormat('MMM d, yyyy').format(day.date)} · $follow';
  }

  static String _resultLabel(ConsistencyDay day, DayResult? result) =>
      switch (result) {
        DayResult.success => 'Success',
        DayResult.started => 'Started',
        DayResult.missed => 'Missed',
        DayResult.empty => 'Neutral',
        DayResult.breakDay => 'Break',
        null => day.isToday ? 'Today so far' : 'Neutral',
      };

  Future<void> _showDayDetails(
    BuildContext context,
    ConsistencyDay day,
    DayResult? result,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(DateFormat('EEEE, MMM d, yyyy').format(day.date)),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (day.isBreak)
              _DetailRow(label: 'Break', value: day.breakLabel!)
            else ...[
              _DetailRow(
                label: 'Planned',
                value: formatMinutes(day.plannedMinutes),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailRow(
                label: 'Actual',
                value: formatMinutes(day.actualMinutes),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DetailRow(
                label: 'Time done',
                value: day.followThroughPercent == null
                    ? 'Neutral'
                    : '${day.followThroughPercent}% · '
                          '${_resultLabel(day, result)}',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Diagonal lines over a neutral cell: a break day, counted in nothing.
class _BreakHatchPainter extends CustomPainter {
  const _BreakHatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final step = math.max(3.0, size.shortestSide / 3);
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BreakHatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

class StreakSummaryView extends StatelessWidget {
  const StreakSummaryView({super.key, required this.streaks});

  final StreakSummary streaks;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.sm,
    children: [
      _StreakChip(
        key: const ValueKey('current-streak'),
        icon: Icons.local_fire_department_outlined,
        label:
            'Current streak: ${streaks.current} '
            '${streaks.current == 1 ? 'day' : 'days'}',
        color: AppThemeTokens.of(context).success,
      ),
      _StreakChip(
        key: const ValueKey('best-streak'),
        icon: Icons.emoji_events_outlined,
        label:
            'Best streak: ${streaks.best} '
            '${streaks.best == 1 ? 'day' : 'days'}',
        color: AppThemeTokens.of(context).warning,
      ),
    ],
  );
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        color.withValues(alpha: 0.12),
        AppThemeTokens.of(context).surfaceRaised,
      ),
      borderRadius: BorderRadius.circular(
        AppThemeTokens.of(context).radiusSmall,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

/// Lightweight semantic progress primitive shared by weekly and category
/// summaries. The expanding child is intentional: a bare ColoredBox has no
/// intrinsic width inside FractionallySizedBox and can collapse to zero.
class InsightsProgressBar extends StatelessWidget {
  const InsightsProgressBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 10,
  });

  final double fraction;
  final Color color;
  final double height;

  double get normalizedFraction =>
      fraction.isFinite ? fraction.clamp(0.0, 1.0).toDouble() : 0.0;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: Container(
      height: height,
      color: AppThemeTokens.of(context).surfaceSubtle,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: normalizedFraction,
        child: SizedBox.expand(child: ColoredBox(color: color)),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(value, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

String formatMinutes(int minutes) {
  final safe = math.max(0, minutes);
  final hours = safe ~/ 60;
  final remainder = safe % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

int _calendarDayDifference(DateTime start, DateTime end) {
  final left = PlannerTimeZone.toPlannerLocal(start);
  final right = PlannerTimeZone.toPlannerLocal(end);
  return DateTime.utc(
    right.year,
    right.month,
    right.day,
  ).difference(DateTime.utc(left.year, left.month, left.day)).inDays;
}
