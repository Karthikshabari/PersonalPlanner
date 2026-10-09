import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../domain/analytics_models.dart';

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
    final weeks = List.generate(
      weekCount,
      (index) => addDays(firstWeek, index * 7),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 34.0;
        const gap = 3.0;
        final available = math.max(0.0, constraints.maxWidth - labelWidth);
        final cellSize = ((available - (weekCount - 1) * gap) / weekCount)
            .clamp(9.0, 16.0);
        final gridWidth = weekCount * cellSize + (weekCount - 1) * gap;
        final calendarWidth = labelWidth + gridWidth;
        final calendar = SizedBox(
          width: calendarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: labelWidth),
                child: SizedBox(
                  width: gridWidth,
                  height: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: _monthLabels(
                      context,
                      weeks,
                      visibleStart,
                      visibleEndExclusive,
                      cellSize,
                      gap,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      children: [
                        for (final label in const [
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
                                    ?.copyWith(
                                      color: AppThemeTokens.of(context)
                                          .textMuted,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
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
                          Column(
                            children: [
                              for (var weekday = 0; weekday < 7; weekday++) ...[
                                _dayCell(
                                  context,
                                  addDays(weeks[weekIndex], weekday),
                                  days[isoDateString(
                                    addDays(weeks[weekIndex], weekday),
                                  )],
                                  cellSize,
                                ),
                                if (weekday < 6) const SizedBox(height: gap),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        final calendarViewport = compact
            ? SingleChildScrollView(
                key: const ValueKey('consistency-grid-scroll'),
                scrollDirection: Axis.horizontal,
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
    final labels = <Widget>[];
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
      labels.add(
        Positioned(
          left: index * (cellSize + gap),
          child: Text(
            DateFormat('MMM').format(representative),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppThemeTokens.of(context).textMuted),
          ),
        ),
      );
    }
    return labels;
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    ConsistencyDay? day,
    double size,
  ) {
    final effectiveDay =
        day ??
        ConsistencyDay(
          date: date,
          plannedMinutes: 0,
          completedPlannedMinutes: 0,
          actualMinutes: 0,
          isFuture: date.isAfter(startOfDay(snapshot.generatedFor)),
        );
    final tokens = AppThemeTokens.of(context);
    final color = switch (effectiveDay.intensity) {
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
    return Tooltip(
      message: _dayTooltip(effectiveDay),
      child: Semantics(
        button: true,
        label: _dayTooltip(effectiveDay),
        child: InkWell(
          key: ValueKey('consistency-day-${isoDateString(date)}'),
          borderRadius: BorderRadius.circular(3),
          onTap: () => _showDayDetails(context, effectiveDay),
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
            ),
          ),
        ),
      ),
    );
  }

  String _dayTooltip(ConsistencyDay day) {
    final context = day.excludedByContext
        ? ' · ${day.context!.shortLabel}'
        : '';
    final follow = day.followThroughPercent == null
        ? 'Neutral'
        : '${day.followThroughPercent}% follow-through';
    return '${DateFormat('MMM d, yyyy').format(day.date)}$context · $follow';
  }

  Future<void> _showDayDetails(BuildContext context, ConsistencyDay day) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(DateFormat('EEEE, MMM d, yyyy').format(day.date)),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (day.excludedByContext) ...[
                  _DetailRow(
                    label: 'Day context',
                    value: day.context!.shortLabel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
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
                  label: 'Follow-through',
                  value: day.followThroughPercent == null
                      ? 'Neutral'
                      : '${day.followThroughPercent}%',
                ),
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
        label: 'Current streak: ${streaks.current} days',
        color: AppThemeTokens.of(context).success,
      ),
      _StreakChip(
        key: const ValueKey('best-streak'),
        icon: Icons.emoji_events_outlined,
        label: 'Best streak: ${streaks.best} days',
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
