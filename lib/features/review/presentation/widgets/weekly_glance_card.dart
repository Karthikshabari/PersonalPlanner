import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import '../../domain/weekly_review_numbers.dart';
import 'dashed_outline.dart';
import 'mood_face.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// "Week at a glance": the big completion line, the counts line and the
/// seven-day strip (spec 3.2). Planned hours are never shown.
class WeeklyGlanceCard extends StatelessWidget {
  const WeeklyGlanceCard({
    super.key,
    required this.numbers,
    required this.future,
    this.today,
  });

  final WeeklyNumbers numbers;

  /// "Today" for the highlight; the device date when null. Injectable for tests.
  final DateTime? today;

  /// The week starts after the current week (WD25).
  final bool future;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final percent = numbers.percent;
    final headline = future
        ? 'This week has not happened yet.'
        : percent == null
        ? 'No tasks this week'
        : '$percent% completed';
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Week at a glance', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            headline,
            key: const ValueKey('weekly-glance-headline'),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (numbers.total > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              numbers.glanceSubline,
              key: const ValueKey('weekly-glance-subline'),
              style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          WeeklyDayStrip(days: numbers.days, today: today ?? DateTime.now()),
        ],
      ),
    );
  }
}

/// Seven day cards. They share the width when there is room for seven 94 dp
/// cards; otherwise the strip scrolls sideways (about 3.5 cards on a phone).
class WeeklyDayStrip extends StatelessWidget {
  const WeeklyDayStrip({super.key, required this.days, this.today});

  final List<WeeklyDayStats> days;
  final DateTime? today;

  /// Today's date when the strip's week contains it, else null.
  DateTime? get _todayInWeek {
    final now = today;
    if (now == null) return null;
    final day = DateTime(now.year, now.month, now.day);
    for (final d in days) {
      if (DateTime(d.date.year, d.date.month, d.date.day) == day) return day;
    }
    return null;
  }

  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    final height = WeeklyDayCard.heightFor(context, days);
    return LayoutBuilder(
      builder: (context, constraints) {
        final needed =
            days.length * WeeklyDayCard.width + (days.length - 1) * gap;
        if (constraints.maxWidth >= needed) {
          return SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: WeeklyDayCard(
                      key: ValueKey('weekly-day-$i'),
                      day: days[i],
                      today: _todayInWeek,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: SingleChildScrollView(
            key: const ValueKey('weekly-day-strip'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: WeeklyDayCard.width,
                    height: height,
                    child: WeeklyDayCard(
                      key: ValueKey('weekly-day-$i'),
                      day: days[i],
                      today: _todayInWeek,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// `Mon Sep 28: 50% done, Good, Office` or `Sat Oct 3: No tasks`.
String weeklyDayCardLabel(WeeklyDayStats day) {
  final date =
      '${DateFormat('EEE').format(day.date)} '
      '${DateFormat('MMM d').format(day.date)}';
  if (day.total == 0) return '$date: No tasks';
  final mood = day.mood;
  final parts = <String>[
    '${day.percent}% done',
    mood != null
        ? reviewMoodLabel(mood)
        : (day.reviewed ? 'Reviewed' : 'Not reviewed'),
    if (day.contextLabel != null) day.contextLabel!,
  ];
  return '$date: ${parts.join(', ')}';
}

/// One day of the strip, in the style of the Overview day cards.
class WeeklyDayCard extends StatelessWidget {
  const WeeklyDayCard({super.key, required this.day, this.today});

  final WeeklyDayStats day;

  /// Set only when the viewed week contains today: that day gets the accent
  /// border and weekday, and the days after it are dimmed.
  final DateTime? today;

  static const double width = 94;
  static const double horizontalPadding = 6;
  static const double verticalPadding = 10;
  static const double gap = 4;
  static const double faceSize = 30;
  static const double barHeight = 4;
  static const double chipExtra = 4;
  static const double contentWidth = width - 2 * horizontalPadding;

  static TextStyle? _weekdayStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600);

  static TextStyle? _smallStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppThemeTokens.of(context).textMuted, fontSize: 12);

  static TextStyle _percentStyle(BuildContext context) =>
      reviewMonoStyle(context, fontSize: 13).copyWith(
        color: AppThemeTokens.of(context).textPrimary,
        fontWeight: FontWeight.w500,
      );

  /// The day-context chip on a reviewed day, `Not reviewed` otherwise.
  static String? _status(WeeklyDayStats day) =>
      day.reviewed ? day.contextLabel : 'Not reviewed';

  /// Height of the tallest card, measured with the real text (line wraps and
  /// text scale included), as the Overview day strip does.
  static double heightFor(BuildContext context, List<WeeklyDayStats> days) {
    double text(String value, TextStyle? style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: contentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var tallest = 0.0;
    for (final day in days) {
      var h = verticalPadding * 2;
      h += text(DateFormat('EEE').format(day.date), _weekdayStyle(context));
      h += gap;
      h += text(DateFormat('MMM d').format(day.date), _smallStyle(context));
      h += gap + faceSize + gap;
      if (day.total == 0) {
        h += text('No tasks', _smallStyle(context));
      } else {
        h += text('${day.percent}%', _percentStyle(context));
        h += gap + barHeight;
        final status = _status(day);
        if (status != null) {
          h += gap;
          h += day.reviewed
              ? text(status, _smallStyle(context), maxLines: 1) + chipExtra
              : text(status, _smallStyle(context));
        }
      }
      tallest = math.max(tallest, h);
    }
    // Whole pixels: a fractional shortfall would still report an overflow.
    return tallest.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final mood = day.mood;
    final status = _status(day);
    const gapBox = SizedBox(height: gap);
    final now = today;
    final dayOnly = DateTime(day.date.year, day.date.month, day.date.day);
    final isToday = now != null && dayOnly == now;
    // Days after today are dimmed through the colours themselves (no Opacity
    // widget, so no offscreen layer).
    final fadeBy = now != null && dayOnly.isAfter(now) ? 0.6 : 1.0;
    Color fade(Color c) =>
        fadeBy == 1.0 ? c : c.withValues(alpha: c.a * fadeBy);
    final accent = Theme.of(context).colorScheme.primary;
    final small = _smallStyle(context)?.copyWith(color: fade(tokens.textMuted));
    return Semantics(
      container: true,
      label: weeklyDayCardLabel(day),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A tonal tile on the card; only today carries a border.
          color: fade(WeeklyStyle.inset(context)),
          borderRadius: BorderRadius.circular(WeeklyStyle.insetRadius(context)),
          border: Border.all(color: isToday ? accent : Colors.transparent),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: horizontalPadding,
          ),
          child: Column(
            children: [
              Text(
                DateFormat('EEE').format(day.date),
                style: _weekdayStyle(
                  context,
                )?.copyWith(color: isToday ? accent : fade(tokens.textPrimary)),
              ),
              gapBox,
              Text(
                DateFormat('MMM d').format(day.date),
                textAlign: TextAlign.center,
                style: small,
              ),
              gapBox,
              if (mood != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fade(
                      ReviewColors.of(context)
                          .mood(mood)
                          .withValues(alpha: 0.16),
                    ),
                  ),
                  child: MoodFace(
                    level: mood,
                    size: faceSize,
                    color: fade(ReviewColors.of(context).mood(mood)),
                  ),
                )
              else
                SizedBox.square(
                  dimension: faceSize,
                  child: CustomPaint(
                    painter: DashedOutlinePainter(
                      color: fade(tokens.textMuted),
                      strokeWidth: 1.5,
                      circle: true,
                    ),
                  ),
                ),
              gapBox,
              if (day.total == 0)
                Text('No tasks', style: small)
              else ...[
                Text(
                  '${day.percent}%',
                  style: _percentStyle(context)
                      .copyWith(color: fade(tokens.textPrimary)),
                ),
                gapBox,
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: day.percent! / 100,
                    minHeight: barHeight,
                    color: fade(ReviewColors.of(context).success),
                    backgroundColor: fade(tokens.outline),
                  ),
                ),
                if (status != null) ...[
                  gapBox,
                  if (day.reviewed)
                    Container(
                      constraints: const BoxConstraints(maxWidth: contentWidth),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: fade(tokens.surface),
                        borderRadius: BorderRadius.circular(
                          WeeklyStyle.pillRadius,
                        ),
                      ),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    )
                  else
                    Text(status, textAlign: TextAlign.center, style: small),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
