import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
import 'dashed_outline.dart';
import 'mood_face.dart';
import 'overview_day_strip.dart';
import 'review_theme.dart';

/// Overview › Weekly: a sideways strip of week cards, newest at the right,
/// with the same arrows, edge fades and lazy loading as the day strip
/// (spec 3.14, WD24). Cards are not interactive in v1.
class OverviewWeekStrip extends ConsumerStatefulWidget {
  const OverviewWeekStrip({super.key});

  @override
  ConsumerState<OverviewWeekStrip> createState() => _OverviewWeekStripState();
}

class _OverviewWeekStripState extends ConsumerState<OverviewWeekStrip> {
  static const _pageSize = 12;
  static const _maxWeeks = 104;
  static const _stripPadding = EdgeInsets.fromLTRB(2, 4, 2, 12);
  final _controller = ScrollController();
  int _weekCount = _pageSize;
  List<WeeklyHistoryWeek> _weeks = const [];

  // The strip is reversed: pixel 0 is the newest end (this week, at the right).
  bool _canScrollOlder = true;
  bool _canScrollNewer = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 300 &&
        _weeks.length >= _weekCount &&
        _weekCount < _maxWeeks) {
      setState(() => _weekCount = math.min(_weekCount + _pageSize, _maxWeeks));
    }
  }

  void _updateEdges(ScrollMetrics metrics) {
    final newer = metrics.pixels > metrics.minScrollExtent + 0.5;
    final older =
        metrics.pixels < metrics.maxScrollExtent - 0.5 ||
        (_weeks.length >= _weekCount && _weekCount < _maxWeeks);
    if (newer == _canScrollNewer && older == _canScrollOlder) return;
    setState(() {
      _canScrollNewer = newer;
      _canScrollOlder = older;
    });
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewOverviewWeekWindowProvider(_weekCount));
    // Keep showing the previous window while a larger one loads.
    if (async.hasValue) _weeks = async.requireValue;
    if (_weeks.isEmpty) {
      if (async.hasError) {
        return ErrorPanel(
          message: friendlyErrorMessage(async.error!),
          compact: true,
        );
      }
      return const LinearProgressIndicator();
    }
    final stripHeight =
        OverviewWeekCard.heightFor(context, _weeks) + _stripPadding.vertical;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArrows = constraints.maxWidth >= 520;
        final list = Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent || !_controller.hasClients) {
              return;
            }
            final delta = event.scrollDelta.dy != 0
                ? event.scrollDelta.dy
                : event.scrollDelta.dx;
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              final p = _controller.position;
              _controller.jumpTo(
                (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent),
              );
            });
          },
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) {
              _updateEdges(n.metrics);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) _updateEdges(n.metrics);
                return false;
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.separated(
                  key: const ValueKey('overview-week-strip'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  reverse: true, // index 0 (this week) sits at the right edge
                  padding: _stripPadding,
                  itemCount: _weeks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final week = _weeks[index];
                    return OverviewWeekCard(
                      key: ValueKey(
                        'overview-week-${isoDateString(week.weekStart)}',
                      ),
                      week: week,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        final strip = SizedBox(
          height: stripHeight,
          child: Stack(
            children: [
              list,
              ReviewStripEdgeFade(
                key: const ValueKey('overview-week-fade-older'),
                alignment: Alignment.centerLeft,
                visible: _canScrollOlder,
              ),
              ReviewStripEdgeFade(
                key: const ValueKey('overview-week-fade-newer'),
                alignment: Alignment.centerRight,
                visible: _canScrollNewer,
              ),
            ],
          ),
        );
        if (!showArrows) return strip;
        return Row(
          children: [
            ReviewStripArrowButton(
              key: const ValueKey('overview-week-older'),
              icon: Icons.chevron_left_rounded,
              tooltip: 'Earlier weeks',
              onPressed: _canScrollOlder ? () => _scrollBy(300) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: strip),
            const SizedBox(width: AppSpacing.sm),
            ReviewStripArrowButton(
              key: const ValueKey('overview-week-newer'),
              icon: Icons.chevron_right_rounded,
              tooltip: 'Later weeks',
              onPressed: _canScrollNewer ? () => _scrollBy(-300) : null,
            ),
          ],
        );
      },
    );
  }
}

/// One week of Overview › Weekly (112 dp wide): the range, the mood face or
/// a dashed placeholder, the completion and the mood name (WD23).
class OverviewWeekCard extends StatelessWidget {
  const OverviewWeekCard({super.key, required this.week});

  final WeeklyHistoryWeek week;

  static const double width = 112;
  static const double horizontalPadding = 8;
  static const double verticalPadding = 10;
  static const double gap = 4;
  static const double faceSize = 34;
  static const double contentWidth = width - 2 * horizontalPadding;

  static String rangeLabel(WeeklyHistoryWeek week) =>
      weekRangeLabel(week.weekStart, addDays(week.weekStart, 6));

  static String percentText(WeeklyHistoryWeek week) =>
      week.percent == null ? 'No tasks' : '${week.percent}%';

  static String stateText(WeeklyHistoryWeek week) {
    final mood = week.mood;
    if (mood != null) return reviewMoodLabel(mood);
    return week.reviewed ? 'Reviewed' : 'Not reviewed';
  }

  /// `Sep 21–27: 45% completed, Good` or `Aug 31–Sep 6: No tasks, Not reviewed`.
  static String semanticsLabel(WeeklyHistoryWeek week) {
    final percent = week.percent;
    final done = percent == null ? 'No tasks' : '$percent% completed';
    return '${rangeLabel(week)}: $done, ${stateText(week)}';
  }

  static TextStyle? _rangeStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600);

  static TextStyle _percentStyle(BuildContext context) =>
      reviewMonoStyle(context, fontSize: 13).copyWith(
        color: AppThemeTokens.of(context).textPrimary,
        fontWeight: FontWeight.w500,
      );

  static TextStyle? _stateStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppThemeTokens.of(context).textMuted);

  /// Height of the tallest card, measured with the real text at the current
  /// text scale (as the day strip does).
  static double heightFor(BuildContext context, List<WeeklyHistoryWeek> weeks) {
    double text(String value, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: contentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var tallest = 0.0;
    for (final week in weeks) {
      final h =
          verticalPadding * 2 +
          text(rangeLabel(week), _rangeStyle(context)) +
          gap +
          faceSize +
          gap +
          text(percentText(week), _percentStyle(context)) +
          gap +
          text(stateText(week), _stateStyle(context));
      tallest = math.max(tallest, h);
    }
    // Whole pixels: a fractional shortfall would still report an overflow.
    return tallest.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final mood = week.mood;
    const gapBox = SizedBox(height: gap);
    return Semantics(
      container: true,
      label: semanticsLabel(week),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: horizontalPadding,
            ),
            child: Column(
              children: [
                Text(
                  rangeLabel(week),
                  textAlign: TextAlign.center,
                  style: _rangeStyle(context),
                ),
                gapBox,
                if (mood != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ReviewColors.of(context)
                          .mood(mood)
                          .withValues(alpha: 0.16),
                    ),
                    child: MoodFace(level: mood, size: faceSize),
                  )
                else
                  SizedBox.square(
                    dimension: faceSize,
                    child: CustomPaint(
                      painter: DashedOutlinePainter(
                        color: tokens.textMuted,
                        strokeWidth: 1.5,
                        circle: true,
                      ),
                    ),
                  ),
                gapBox,
                Text(percentText(week), style: _percentStyle(context)),
                gapBox,
                Text(
                  stateText(week),
                  textAlign: TextAlign.center,
                  style: _stateStyle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
