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
  final _controller = ScrollController();
  int _dayCount = _pageSize;
  List<ReviewOverviewDay> _days = const [];
  DateTime? _selected; // null = today (index 0)

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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stripHeight = 196 + 64 * (scale - 1).clamp(0.0, 1.0);

    final strip = LayoutBuilder(
      builder: (context, constraints) {
        final showArrows = constraints.maxWidth >= 520;
        final strip = SizedBox(
          height: stripHeight,
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent || !_controller.hasClients) {
                return;
              }
              final delta = event.scrollDelta.dy != 0
                  ? event.scrollDelta.dy
                  : event.scrollDelta.dx;
              GestureBinding.instance.pointerSignalResolver.register(event, (
                _,
              ) {
                final p = _controller.position;
                _controller.jumpTo(
                  (p.pixels + delta).clamp(
                    p.minScrollExtent,
                    p.maxScrollExtent,
                  ),
                );
              });
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
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
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
        );
        if (!showArrows) return strip;
        return Row(
          children: [
            _ArrowButton(
              key: const ValueKey('overview-older'),
              icon: Icons.chevron_left_rounded,
              tooltip: 'Earlier days',
              onPressed: () => _scrollBy(300),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: strip),
            const SizedBox(width: AppSpacing.sm),
            _ArrowButton(
              key: const ValueKey('overview-newer'),
              icon: Icons.chevron_right_rounded,
              tooltip: 'Later days',
              onPressed: () => _scrollBy(-300),
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

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

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

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final muted = tokens.textMuted;
    final mood = day.mood;
    final dayContext = day.dayContext;
    const gap = SizedBox(height: 5);

    return Semantics(
      button: true,
      selected: selected,
      label: overviewDetailLine(day),
      child: SizedBox(
        width: 94,
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
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEE').format(day.date),
                    style: reviewMonoStyle(
                      context,
                      fontSize: 10.5,
                    ).copyWith(color: isToday ? colorScheme.primary : null),
                  ),
                  gap,
                  Text(
                    DateFormat('MMM d').format(day.date),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: _tabular,
                    ),
                  ),
                  gap,
                  if (mood != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ReviewColors.of(context)
                            .mood(mood)
                            .withValues(alpha: 0.16),
                      ),
                      child: MoodFace(level: mood, size: 38),
                    )
                  else
                    SizedBox.square(
                      dimension: 38,
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
                  gap,
                  if (day.percent == null)
                    Text(
                      'No tasks',
                      style: textTheme.labelSmall?.copyWith(color: muted),
                    )
                  else ...[
                    Text(
                      '${day.percent}%',
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: _tabular,
                      ),
                    ),
                    gap,
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: day.percent! / 100,
                        minHeight: 4,
                      ),
                    ),
                    if (!day.reviewed) ...[
                      gap,
                      Text(
                        'Not reviewed',
                        style: textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                  if (dayContext != null) ...[
                    gap,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dayContextIcon(dayContext.kind),
                          size: 13,
                          color: muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            dayContext.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(color: muted),
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
