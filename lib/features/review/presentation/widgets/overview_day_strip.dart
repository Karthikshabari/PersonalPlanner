import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/day_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../day_context/presentation/day_context_icon.dart';
import '../../domain/review_mood.dart';
import '../../domain/review_overview.dart';
import '../../providers/review_providers.dart';
import 'overview_strip.dart';
import 'review_theme.dart';

/// Everything one day tile shows, computed once when its window loads so the
/// tile's build does no formatting.
class OverviewDayTile {
  OverviewDayTile(this.day, {required this.isToday})
    : date = day.date,
      key = isoDateString(day.date),
      weekday = isToday ? 'Today' : _weekdayFormat.format(day.date),
      dateLabel = _dateFormat.format(day.date),
      status = day.mood == null ? 'Not reviewed' : reviewMoodLabel(day.mood!),
      contextLabel = day.dayContext?.displayLabel;

  static final _weekdayFormat = DateFormat('EEE');
  static final _dateFormat = DateFormat('MMM d');

  final ReviewOverviewDay day;
  final DateTime date;
  final bool isToday;

  /// `yyyy-MM-dd`, used in widget keys.
  final String key;

  /// `Today` or the short weekday.
  final String weekday;

  /// `Oct 9`.
  final String dateLabel;

  /// The tier name, or `Not reviewed`.
  final String status;
  final String? contextLabel;

  /// `Fri Oct 9, Good, 33% done` (the screen reader adds "selected").
  late final String semanticsLabel = [
    '${_weekdayFormat.format(date)} $dateLabel',
    if (isToday) 'today',
    status,
    day.percent == null ? 'No tasks' : '${day.percent}% done',
    ?contextLabel,
  ].join(', ');
}

/// Overview › Days: a lazy, sideways strip of day tiles (newest at the right),
/// the selected day's summary with "Open this day", and the tier legend. All
/// tile data comes from one windowed provider; tiles read no providers.
class OverviewDayStrip extends ConsumerStatefulWidget {
  const OverviewDayStrip({super.key, this.wide = true});

  /// Wide content column: the summary and the button share one row.
  final bool wide;

  @override
  ConsumerState<OverviewDayStrip> createState() => _OverviewDayStripState();
}

class _OverviewDayStripState extends ConsumerState<OverviewDayStrip> {
  static const _pageSize = 30;
  static const _maxDays = 730;

  int _dayCount = _pageSize;
  List<ReviewOverviewDay> _days = const [];
  List<OverviewDayTile> _tiles = const [];
  Map<DateTime, int> _indexByDate = const {};
  bool _hasContext = false;
  OverviewSelection<DateTime>? _selection;
  OverviewTileMetrics? _metrics;
  bool _metricsHaveContext = false;

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

  /// Builds the per-day display data once for a freshly loaded window.
  void _setDays(List<ReviewOverviewDay> days) {
    _days = days;
    _tiles = [
      for (var i = 0; i < days.length; i++)
        OverviewDayTile(days[i], isToday: i == 0),
    ];
    _indexByDate = {for (var i = 0; i < days.length; i++) days[i].date: i};
    _hasContext = days.any((d) => d.dayContext != null);
    _selection ??= OverviewSelection(days.first.date);
  }

  void _loadMore() {
    if (_dayCount >= _maxDays) return;
    setState(() => _dayCount = math.min(_dayCount + _pageSize, _maxDays));
  }

  void _openDay(DateTime date) {
    ref.read(selectedReviewDateProvider.notifier).state = date;
    if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      context.go('/review');
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/review');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewOverviewWindowProvider(_dayCount));
    // Keep showing the previous window while a larger one loads so the strip
    // never jumps.
    if (async.hasValue && !identical(async.requireValue, _days)) {
      _setDays(async.requireValue);
    }
    if (_days.isEmpty) {
      if (async.hasError) {
        return ErrorPanel(
          message: friendlyErrorMessage(async.error!),
          compact: true,
        );
      }
      return const LinearProgressIndicator();
    }
    if (_metrics == null || _metricsHaveContext != _hasContext) {
      _metricsHaveContext = _hasContext;
      _metrics = OverviewTileMetrics.measure(
        context,
        weeks: false,
        hasContext: _hasContext,
      );
    }
    final selection = _selection!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewStrip(
          keyPrefix: 'overview',
          listKey: const ValueKey('overview-strip'),
          itemCount: _tiles.length,
          tileMetrics: _metrics!,
          hasMore: _days.length >= _dayCount && _dayCount < _maxDays,
          onLoadMore: _loadMore,
          olderTooltip: 'Earlier days',
          newerTooltip: 'Later days',
          itemBuilder: (context, index) {
            final tile = _tiles[index];
            return OverviewTileFrame(
              key: ValueKey('overview-day-${tile.key}'),
              selected: selection.flag(tile.date),
              label: tile.semanticsLabel,
              onSelect: () => selection.select(tile.date),
              child: OverviewDayTileBody(tile: tile),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        OverviewDaySummary(
          selection: selection.listenable,
          days: _days,
          indexByDate: _indexByDate,
          wide: widget.wide,
          onOpen: _openDay,
        ),
        const SizedBox(height: AppSpacing.md),
        const OverviewLegend(),
      ],
    );
  }
}

/// The selected day's detail line and "Open this day". Listens only to the
/// selection, so it is the one widget besides the two tiles that changes.
class OverviewDaySummary extends StatelessWidget {
  const OverviewDaySummary({
    super.key,
    required this.selection,
    required this.days,
    required this.indexByDate,
    required this.wide,
    required this.onOpen,
  });

  final ValueListenable<DateTime> selection;
  final List<ReviewOverviewDay> days;
  final Map<DateTime, int> indexByDate;
  final bool wide;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: selection,
      builder: (context, date, _) {
        final day = days[indexByDate[date] ?? 0];
        final detail = Text(
          overviewDetailLine(day),
          key: const ValueKey('overview-detail'),
          style: Theme.of(context).textTheme.bodyMedium,
        );
        final button = SizedBox(
          height: 48,
          width: wide ? null : double.infinity,
          child: OutlinedButton(
            key: const ValueKey('overview-open-day'),
            onPressed: () => onOpen(day.date),
            child: const Text('Open this day'),
          ),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: detail),
              const SizedBox(width: AppSpacing.lg),
              button,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            detail,
            const SizedBox(height: AppSpacing.sm),
            button,
          ],
        );
      },
    );
  }
}

/// The content of one day tile: weekday, date, face, completion, bar and the
/// status tags. Built once per tile; selection, hover and focus are the
/// frame's business.
class OverviewDayTileBody extends StatelessWidget {
  const OverviewDayTileBody({super.key, required this.tile});

  final OverviewDayTile tile;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final day = tile.day;
    final mood = day.mood;
    final dayContext = day.dayContext;
    const gap = SizedBox(height: OverviewTileMetrics.gap);
    return Column(
      children: [
        Text(
          tile.weekday,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OverviewTileText.caption(context)
              .copyWith(color: tile.isToday ? accent : null),
        ),
        gap,
        Text(
          tile.dateLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OverviewTileText.date(context),
        ),
        gap,
        OverviewTileFace(mood: mood),
        gap,
        if (day.percent == null)
          Text(
            'No tasks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OverviewTileText.caption(context),
          )
        else
          Text(
            '${day.percent}%',
            maxLines: 1,
            style: OverviewTileText.percent(context),
          ),
        gap,
        OverviewTileProgress(percent: day.percent),
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
        if (dayContext != null) ...[
          gap,
          OverviewTag(
            label: tile.contextLabel!,
            icon: dayContextIcon(dayContext.kind),
          ),
        ],
      ],
    );
  }
}
