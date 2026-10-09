import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/weekly_review_numbers.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// "What got in the way": reasons of every task that was not completed,
/// "No reason given", and the Day types lines (spec 3.4).
class WeeklyReasonsCard extends StatefulWidget {
  const WeeklyReasonsCard({super.key, required this.numbers});

  final WeeklyNumbers numbers;

  @override
  State<WeeklyReasonsCard> createState() => _WeeklyReasonsCardState();
}

class _WeeklyReasonsCardState extends State<WeeklyReasonsCard> {
  /// Local UI state only.
  bool _expanded = false;

  /// More rows than this collapse to [_collapsedRows] plus a button.
  static const int _maxRows = 5;
  static const int _collapsedRows = 4;

  @override
  Widget build(BuildContext context) {
    final numbers = widget.numbers;
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: tokens.textMuted);
    final reasons = numbers.reasonCounts;
    final noReason = numbers.noReasonCount;
    final maxCount = [
      1,
      noReason,
      if (reasons.isNotEmpty) reasons.first.count,
    ].reduce(math.max);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What got in the way', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (numbers.total == 0)
            Text('No tasks this week.', style: muted)
          else if (!numbers.hasMissedTasks)
            Text('Nothing to show. Everything planned got done.', style: muted)
          else ...[
            ...() {
              final bars = <Widget>[
                for (final reason in reasons)
                  _ReasonBar(
                    key: ValueKey('weekly-reason-${reason.reason}'),
                    label: reason.reason,
                    count: reason.count,
                    max: maxCount,
                  ),
                if (noReason > 0)
                  _ReasonBar(
                    key: const ValueKey('weekly-reason-none'),
                    label: 'No reason given',
                    count: noReason,
                    max: maxCount,
                    muted: true,
                  ),
              ];
              if (bars.length <= _maxRows) return bars;
              return [
                ...(_expanded ? bars : bars.take(_collapsedRows)),
                WeeklyShowAllButton(
                  key: const ValueKey('weekly-reasons-show-all'),
                  expanded: _expanded,
                  total: bars.length,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ];
            }(),
          ],
          if (numbers.dayTypes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Day types', style: weeklyCaptionStyle(context)),
            const SizedBox(height: AppSpacing.xs),
            for (final type in numbers.dayTypes)
              _DayTypeLine(
                key: ValueKey('weekly-day-type-${type.label}'),
                type: type,
              ),
          ],
        ],
      ),
    );
  }
}

class _ReasonBar extends StatelessWidget {
  const _ReasonBar({
    super.key,
    required this.label,
    required this.count,
    required this.max,
    this.muted = false,
  });

  final String label;
  final int count;
  final int max;
  final bool muted;

  static const double _labelWidth = 112;
  static const double _barHeight = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        container: true,
        label: '$label: $count',
        excludeSemantics: true,
        child: Row(
          children: [
            Tooltip(
              message: label,
              child: SizedBox(
                width: _labelWidth,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: muted ? tokens.textMuted : tokens.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // A visible track, so a full bar still reads as a bar and not as
            // a divider line. The bar length is still count / max.
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: WeeklyStyle.inset(context),
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  child: LinearProgressIndicator(
                    value: count / max,
                    minHeight: _barHeight,
                    color: ReviewColors.of(context).blue,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // A fixed column so the counts line up under each other.
            SizedBox(
              width: 32,
              child: Text(
                '×$count',
                textAlign: TextAlign.end,
                maxLines: 1,
                style: weeklyCaptionStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTypeLine extends StatelessWidget {
  const _DayTypeLine({super.key, required this.type});

  final WeeklyDayType type;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: tokens.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Wrap(
        spacing: 10,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: WeeklyStyle.inset(context),
              borderRadius: BorderRadius.circular(WeeklyStyle.pillRadius),
            ),
            child: Text(type.label, style: small),
          ),
          Text(type.days == 1 ? '1 day' : '${type.days} days', style: small),
          Text(
            '${type.completed} of ${type.total} tasks done',
            style: reviewMonoStyle(context, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
