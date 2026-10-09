import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
import 'dashed_outline.dart';
import 'mood_face.dart';
import 'review_theme.dart';

/// Horizontally scrolling strip of day cards, newest at the right, with the
/// selected day's detail line, "Open this day" and a mood legend. All card
/// data comes from one windowed provider; cards build no per-day providers.
class OverviewDayStrip extends ConsumerStatefulWidget {
  const OverviewDayStrip({super.key});

  @override
  ConsumerState<OverviewDayStrip> createState() => _OverviewDayStripState();
}

class _OverviewDayStripState extends ConsumerState<OverviewDayStrip> {
  static const _pageSize = 30;
  static const _maxDays = 730;
  static const _stripPadding = EdgeInsets.fromLTRB(2, 4, 2, 12);
  final _controller = ScrollController();
  int _dayCount = _pageSize;
  List<ReviewOverviewDay> _days = const [];
  DateTime? _selected; // null = today (index 0)

  // The strip is reversed: pixel 0 is the newest end (today, at the right).
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
        _days.length >= _dayCount &&
        _dayCount < _maxDays) {
      setState(() => _dayCount = math.min(_dayCount + _pageSize, _maxDays));
    }
  }

  void _updateEdges(ScrollMetrics metrics) {
    final newer = metrics.pixels > metrics.minScrollExtent + 0.5;
    // More days can still be loaded beyond the loaded window.
    final older =
        metrics.pixels < metrics.maxScrollExtent - 0.5 ||
        (_days.length >= _dayCount && _dayCount < _maxDays);
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
    if (async.hasValue) _days = async.requireValue;
    if (_days.isEmpty) {
      if (async.hasError) {
        return ErrorPanel(
          message: friendlyErrorMessage(async.error!),
          compact: true,
        );
      }
      return const LinearProgressIndicator();
    }
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selectedDay = _days.firstWhere(
      (d) => _selected != null && d.date == _selected,
      orElse: () => _days.first,
    );
    // Cards share one height, taken from the tallest card in the window at the
    // current text scale, so content never overflows and short content leaves
    // no dead space.
    final metrics = OverviewCardMetrics(context);
    var cardHeight = 0.0;
    for (var i = 0; i < _days.length; i++) {
      cardHeight = math.max(cardHeight, metrics.heightFor(_days[i], i == 0));
    }
    final stripHeight = cardHeight + _stripPadding.vertical;

    final strip = LayoutBuilder(
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
                  key: const ValueKey('overview-strip'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  reverse: true, // index 0 (today) sits at the right edge
                  padding: _stripPadding,
                  itemCount: _days.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final day = _days[index];
                    return OverviewDayCard(
                      key: ValueKey('overview-day-${isoDateString(day.date)}'),
                      day: day,
                      isToday: index == 0,
                      selected:
                          identical(day, selectedDay) ||
                          day.date == selectedDay.date,
                      onTap: () => setState(() => _selected = day.date),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        // Soft fades only at the edges that have more content beyond them.
        final strip = SizedBox(
          height: stripHeight,
          child: Stack(
            children: [
              list,
              ReviewStripEdgeFade(
                key: const ValueKey('overview-fade-older'),
                alignment: Alignment.centerLeft,
                visible: _canScrollOlder,
              ),
              ReviewStripEdgeFade(
                key: const ValueKey('overview-fade-newer'),
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
              key: const ValueKey('overview-older'),
              icon: Icons.chevron_left_rounded,
              tooltip: 'Earlier days',
              onPressed: _canScrollOlder ? () => _scrollBy(300) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: strip),
            const SizedBox(width: AppSpacing.sm),
            ReviewStripArrowButton(
              key: const ValueKey('overview-newer'),
              icon: Icons.chevron_right_rounded,
              tooltip: 'Later days',
              onPressed: _canScrollNewer ? () => _scrollBy(-300) : null,
            ),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        strip,
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Text(
              overviewDetailLine(selectedDay),
              key: const ValueKey('overview-detail'),
            ),
            OutlinedButton(
              key: const ValueKey('overview-open-day'),
              onPressed: () => _openDay(selectedDay.date),
              child: const Text('Open this day'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          key: const ValueKey('overview-legend'),
          spacing: 14,
          runSpacing: 6,
          children: [
            for (var level = 1; level <= 4; level++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MoodFace(level: level, size: 18),
                  const SizedBox(width: 5),
                  Text(
                    reviewMoodLabel(level),
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Gradient from the surface colour to transparent over the first pixels of a
/// scrolling edge. It uses the surface token, so it follows light and dark
/// themes, ignores pointers, and cross-fades only when animations are on.
class ReviewStripEdgeFade extends StatelessWidget {
  const ReviewStripEdgeFade({
    super.key,
    required this.alignment,
    required this.visible,
  });

  static const double width = 28;

  final Alignment alignment;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final surface = AppThemeTokens.of(context).surface;
    final left = alignment == Alignment.centerLeft;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: width,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: alignment,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [surface, surface.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReviewStripArrowButton extends StatelessWidget {
  const ReviewStripArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          side: BorderSide(color: tokens.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// Text styles of a day card, shared by the card and by [OverviewCardMetrics]
/// so the strip height is measured with exactly the styles the card renders.
class _CardStyles {
  _CardStyles(BuildContext context)
    : weekday = reviewMonoStyle(context, fontSize: 10.5),
      date = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: OverviewDayCard._tabular,
      ),
      percent = Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: OverviewDayCard._tabular,
      ),
      small = Theme.of(context).textTheme.labelSmall;

  final TextStyle weekday;
  final TextStyle? date;
  final TextStyle? percent;
  final TextStyle? small;
}

/// Measures the height a day card needs, from the real text (including line
/// wraps) at the current text scale. The strip uses the tallest card in the
/// window, so cards never overflow and are no taller than their content needs.
class OverviewCardMetrics {
  OverviewCardMetrics(this._context) : _styles = _CardStyles(_context);

  final BuildContext _context;
  final _CardStyles _styles;
  final _cache = <String, double>{};

  double _text(String key, String text, TextStyle? style, {int? maxLines}) {
    return _cache.putIfAbsent('$key|$text', () {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(_context).style.merge(style),
        ),
        textDirection: Directionality.of(_context),
        textScaler: MediaQuery.textScalerOf(_context),
        maxLines: maxLines,
      )..layout(maxWidth: OverviewDayCard.contentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    });
  }

  /// Height of the card for [day]; [isToday] is the first card of the strip.
  double heightFor(ReviewOverviewDay day, bool isToday) {
    const gap = OverviewDayCard.gap;
    var h = OverviewDayCard.verticalPadding * 2;
    h += _text(
      'weekday',
      isToday ? 'Today' : DateFormat('EEE').format(day.date),
      _styles.weekday,
    );
    h += gap;
    h += _text('date', DateFormat('MMM d').format(day.date), _styles.date);
    h += gap + OverviewDayCard.faceSize + gap;
    if (day.percent == null) {
      h += _text('small', 'No tasks', _styles.small);
    } else {
      h += _text('percent', '${day.percent}%', _styles.percent);
      h += gap + OverviewDayCard.barHeight;
      if (!day.reviewed) {
        h += gap + _text('small', 'Not reviewed', _styles.small);
      }
    }
    final dayContext = day.dayContext;
    if (dayContext != null) {
      h +=
          gap +
          math.max(
            OverviewDayCard.contextIconSize,
            _text(
              'context',
              dayContext.displayLabel,
              _styles.small,
              maxLines: 1,
            ),
          );
    }
    // Whole pixels: a fractional shortfall would still report an overflow.
    return h.ceilToDouble();
  }
}

class OverviewDayCard extends StatelessWidget {
  const OverviewDayCard({
    super.key,
    required this.day,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final ReviewOverviewDay day;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  static const _tabular = [FontFeature.tabularFigures()];
  static const double width = 94;
  static const double horizontalPadding = 6;
  static const double verticalPadding = 10;
  static const double gap = 5;
  static const double faceSize = 38;
  static const double barHeight = 4;
  static const double contextIconSize = 13;
  static const double contentWidth = width - 2 * horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final styles = _CardStyles(context);
    final muted = tokens.textMuted;
    final mood = day.mood;
    final dayContext = day.dayContext;
    const gapBox = SizedBox(height: gap);

    return Semantics(
      button: true,
      selected: selected,
      label: overviewDetailLine(day),
      child: SizedBox(
        width: width,
        child: Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? colorScheme.primary : tokens.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: verticalPadding,
                horizontal: horizontalPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEE').format(day.date),
                    style: styles.weekday.copyWith(
                      color: isToday ? colorScheme.primary : null,
                    ),
                  ),
                  gapBox,
                  Text(
                    DateFormat('MMM d').format(day.date),
                    style: styles.date,
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
                          color: tokens.outline,
                          strokeWidth: 1.5,
                          circle: true,
                        ),
                        child: Center(
                          child: Text(
                            '–',
                            style: textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ),
                      ),
                    ),
                  gapBox,
                  if (day.percent == null)
                    Text(
                      'No tasks',
                      style: styles.small?.copyWith(color: muted),
                    )
                  else ...[
                    Text('${day.percent}%', style: styles.percent),
                    gapBox,
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: day.percent! / 100,
                        minHeight: barHeight,
                      ),
                    ),
                    if (!day.reviewed) ...[
                      gapBox,
                      Text(
                        'Not reviewed',
                        style: styles.small?.copyWith(color: muted),
                      ),
                    ],
                  ],
                  if (dayContext != null) ...[
                    gapBox,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dayContextIcon(dayContext.kind),
                          size: contextIconSize,
                          color: muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            dayContext.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.small?.copyWith(color: muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
