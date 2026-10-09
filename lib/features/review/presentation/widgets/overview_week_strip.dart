import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/review_mood.dart';
import '../../domain/weekly_review_history.dart';
import '../../domain/weekly_review_numbers.dart';
import '../../providers/review_providers.dart';
import 'overview_strip.dart';
import 'review_theme.dart';

/// Everything one week tile shows, computed once when its window loads.
class OverviewWeekTile {
  OverviewWeekTile(this.week, {required this.isCurrent})
    : weekStart = week.weekStart,
      key = isoDateString(week.weekStart),
      range = weekRangeLabel(week.weekStart, addDays(week.weekStart, 6)),
      status = week.mood != null
          ? reviewMoodLabel(week.mood!)
          : (week.reviewed ? 'Reviewed' : 'Not reviewed');

  final WeeklyHistoryWeek week;
  final DateTime weekStart;
  final bool isCurrent;

  /// `yyyy-MM-dd` of the week start, used in widget keys.
  final String key;

  /// `Aug 31–Sep 6`.
  final String range;

  /// The tier name, `Reviewed` (a review without a tier) or `Not reviewed`.
  final String status;

  /// `Sep 21–27, Good, 45% done` (the screen reader adds "selected").
  late final String semanticsLabel = [
    range,
    if (isCurrent) 'this week',
    status,
    week.percent == null ? 'No tasks' : '${week.percent}% done',
  ].join(', ');
}

/// Overview › Weeks: a lazy, sideways strip of week tiles, newest at the
/// right, with the same arrows, edge fades and lazy loading as the day strip,
/// and the tier legend. The current week starts selected; the selection is
/// local and drives only the highlight, because a week has no detail line or
/// "open" action to show.
class OverviewWeekStrip extends ConsumerStatefulWidget {
  const OverviewWeekStrip({super.key});

  @override
  ConsumerState<OverviewWeekStrip> createState() => _OverviewWeekStripState();
}

class _OverviewWeekStripState extends ConsumerState<OverviewWeekStrip> {
  static const _pageSize = 12;
  static const _maxWeeks = 104;

  int _weekCount = _pageSize;
  List<WeeklyHistoryWeek> _weeks = const [];
  List<OverviewWeekTile> _tiles = const [];
  OverviewSelection<DateTime>? _selection;
  OverviewTileMetrics? _metrics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metrics = null; // text scale, theme or font changed
  }

  @override
  void dispose() {
    _selection?.dispose();
    super.dispose();
  }

  void _setWeeks(List<WeeklyHistoryWeek> weeks) {
    _weeks = weeks;
    _tiles = [
      for (var i = 0; i < weeks.length; i++)
        OverviewWeekTile(weeks[i], isCurrent: i == 0),
    ];
    _selection ??= OverviewSelection(weeks.first.weekStart);
  }

  void _loadMore() {
    if (_weekCount >= _maxWeeks) return;
    setState(() => _weekCount = math.min(_weekCount + _pageSize, _maxWeeks));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewOverviewWeekWindowProvider(_weekCount));
    // Keep showing the previous window while a larger one loads.
    if (async.hasValue && !identical(async.requireValue, _weeks)) {
      _setWeeks(async.requireValue);
    }
    if (_weeks.isEmpty) {
      if (async.hasError) {
        return ErrorPanel(
          message: friendlyErrorMessage(async.error!),
          compact: true,
        );
      }
      return const LinearProgressIndicator();
    }
    _metrics ??= OverviewTileMetrics.measure(
      context,
      weeks: true,
      hasContext: false,
    );
    final selection = _selection!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewStrip(
          keyPrefix: 'overview-week',
          listKey: const ValueKey('overview-week-strip'),
          itemCount: _tiles.length,
          tileMetrics: _metrics!,
          hasMore: _weeks.length >= _weekCount && _weekCount < _maxWeeks,
          onLoadMore: _loadMore,
          olderTooltip: 'Earlier weeks',
          newerTooltip: 'Later weeks',
          itemBuilder: (context, index) {
            final tile = _tiles[index];
            return OverviewTileFrame(
              key: ValueKey('overview-week-${tile.key}'),
              selected: selection.flag(tile.weekStart),
              label: tile.semanticsLabel,
              onSelect: () => selection.select(tile.weekStart),
              child: OverviewWeekTileBody(tile: tile),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const OverviewLegend(),
      ],
    );
  }
}

/// The content of one week tile: range, face, completion, bar and the status
/// tag. Built once per tile.
class OverviewWeekTileBody extends StatelessWidget {
  const OverviewWeekTileBody({super.key, required this.tile});

  final OverviewWeekTile tile;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final week = tile.week;
    final mood = week.mood;
    const gap = SizedBox(height: OverviewTileMetrics.gap);
    return Column(
      children: [
        Text(
          tile.range,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OverviewTileText.date(context),
        ),
        gap,
        OverviewTileFace(mood: mood),
        gap,
        if (week.percent == null)
          Text(
            'No tasks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OverviewTileText.caption(context),
          )
        else
          Text(
            '${week.percent}%',
            maxLines: 1,
            style: OverviewTileText.percent(context),
          ),
        gap,
        OverviewTileProgress(percent: week.percent),
        gap,
        OverviewTag(
          label: tile.status,
          color: mood == null
              ? tokens.textMuted
              : overviewReadable(
                  ReviewColors.of(context).mood(mood),
                  tokens.surface,
                  tokens.textPrimary,
                ),
        ),
      ],
    );
  }
}
