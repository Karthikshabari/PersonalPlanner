import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import '../../domain/weekly_review_numbers.dart';
import 'dashed_outline.dart';
import 'mood_face.dart';
import 'review_header_body.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// Milliseconds on the reveal timeline, measured from the first save
/// (spec 3.7). One [AnimationController] of [total] ms drives all of it.
abstract final class WeeklyRevealTimeline {
  static const int total = 1500;
  static const int ringEnd = 750;
  static const int face = 600;
  static const int moodWord = 650;
  static const int message = 750;
  static const int delta = 850;
  static const int glow = 900;
  static const int chips = 950;
  static const int chipStep = 90;
  static const int signOff = 1150;
  static const int dot = 1250;

  /// Fade-and-rise of each text step.
  static const int step = 250;
}

/// "Your week": before the first save a dashed face and an invitation; after
/// it the ring, face, mood words, delta, highlights, sign-off and the
/// eight-week dots. Animates only when [playToken] changes; otherwise (and
/// with reduced motion) it shows the final state. Wrapped in a
/// [RepaintBoundary] so the animation repaints only this card.
class WeeklyRevealCard extends StatefulWidget {
  const WeeklyRevealCard({
    super.key,
    required this.revealed,
    required this.mood,
    required this.percent,
    required this.deltaText,
    required this.highlights,
    required this.feeling,
    required this.dots,
    required this.playToken,
  });

  /// A saved review with a mood exists for the week.
  final bool revealed;

  /// Saved mood 1..4 (used when [revealed]).
  final int mood;

  /// Week completion; null when the week has no tasks.
  final int? percent;
  final String? deltaText;
  final List<String> highlights;

  /// Saved "How did the week feel?" text ('' for none).
  final String feeling;

  /// Eight dots, oldest first; the last one is this week.
  final List<WeeklyDot> dots;

  /// Bumped by the screen on the first save of the week in this session.
  final int playToken;

  @override
  State<WeeklyRevealCard> createState() => _WeeklyRevealCardState();
}

/// How "Your week" is arranged, chosen from the card's own inner width.
enum _RevealLayout {
  /// Ring on the left, text on the right, the eight-week dots along the
  /// bottom.
  compact,

  /// Everything stacked and centred.
  stacked,
}

class _WeeklyRevealCardState extends State<WeeklyRevealCard>
    with SingleTickerProviderStateMixin {
  /// Inner width from which the ring sits beside the text.
  static const double _compactWidth = 360;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: WeeklyRevealTimeline.total),
    value: 1,
  );

  @override
  void didUpdateWidget(WeeklyRevealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playToken != oldWidget.playToken) _play();
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
    final percent = widget.percent;
    final words = '${reviewMoodLabel(widget.mood)} week';
    SemanticsService.sendAnnouncement(
      View.of(context),
      percent == null ? '$words.' : '$words. $percent percent completed.',
      Directionality.of(context),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = AppThemeTokens.of(context);
    // Once revealed the card carries a very faint, static tint of its tier
    // colour (6 % alpha); the tint cross-fades with the tier.
    final tint = widget.revealed
        ? Color.alphaBlend(
            ReviewColors.of(context)
                .mood(widget.mood.clamp(1, 4))
                .withValues(alpha: 0.06),
            tokens.surface,
          )
        : tokens.surface;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint),
      duration: WeeklyStyle.contentFor(context),
      builder: (context, color, _) => AppSurface(
        color: color,
        child: ReviewHeaderBody(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your week', style: textTheme.titleMedium),
              const SizedBox(height: WeeklyStyle.titleGap),
            ],
          ),
          // Centred in the height the row gives this card.
          body: widget.revealed
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = constraints.maxWidth >= _compactWidth
                        ? _RevealLayout.compact
                        : _RevealLayout.stacked;
                    return AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) =>
                          _after(context, _controller.value, layout),
                    );
                  },
                )
              : _before(context),
        ),
      ),
    );
  }

  Widget _before(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same height as the ring area, so the card does not jump when
        // the ring replaces the placeholder.
        SizedBox(
          height: WeeklyRingPainter.size + 2 * AppSpacing.sm,
          child: Center(
            child: SizedBox.square(
              key: const ValueKey('weekly-reveal-placeholder'),
              dimension: 72,
              child: CustomPaint(
                painter: DashedOutlinePainter(
                  color: tokens.textMuted,
                  strokeWidth: 1.5,
                  circle: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Save your review to reveal your week.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        WeeklyDotsRow(
          dots: widget.dots,
          currentFill: 0,
          reviewedCount: weeklyReviewedDotCount(
            widget.dots,
            currentSaved: false,
          ),
        ),
      ],
    );
  }

  /// [t] is the controller value (0..1 over 1500 ms).
  /// The tier colour cross-fades over 200 ms when the rating changes (not
  /// with reduced motion); the first build shows the final colour at once.
  Widget _after(BuildContext context, double t, _RevealLayout layout) {
    final target = ReviewColors.of(context).mood(widget.mood.clamp(1, 4));
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      builder: (context, color, _) =>
          _afterContent(context, t, layout, color ?? target),
    );
  }

  Widget _afterContent(
    BuildContext context,
    double t,
    _RevealLayout layout,
    Color moodColor,
  ) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final mood = widget.mood.clamp(1, 4);
    final percent = widget.percent;
    const total = WeeklyRevealTimeline.total;

    double interval(int startMs, int lengthMs, [Curve curve = Curves.ease]) =>
        Interval(
          startMs / total,
          math.min(1.0, (startMs + lengthMs) / total),
          curve: curve,
        ).transform(t);
    double step(int startMs) => interval(startMs, WeeklyRevealTimeline.step);

    final ring = interval(
      0,
      WeeklyRevealTimeline.ringEnd,
      const Cubic(0.2, 0.7, 0.2, 1),
    );
    final count = interval(
      0,
      WeeklyRevealTimeline.ringEnd,
      Curves.easeOutCubic,
    );
    final faceScale = interval(
      WeeklyRevealTimeline.face,
      300,
      const Cubic(0.3, 1.6, 0.5, 1),
    );
    final faceOpacity = interval(WeeklyRevealTimeline.face, 200, Curves.linear);
    final sparkle = interval(
      WeeklyRevealTimeline.face,
      total - WeeklyRevealTimeline.face,
      Curves.easeOut,
    );
    final glow = mood >= 3 && t * total >= WeeklyRevealTimeline.glow;
    final dotFill = step(WeeklyRevealTimeline.dot);
    final countText = percent == null ? '–' : '${(percent * count).round()}%';
    final sparkles = switch (mood) {
      1 => 0,
      2 => 1,
      3 => 2,
      _ => 3,
    };
    final feeling = widget.feeling.trim();

    final stacked = layout == _RevealLayout.stacked;
    final textAlign = stacked ? TextAlign.center : TextAlign.start;
    final wrapAlignment = stacked ? WrapAlignment.center : WrapAlignment.start;
    final blockAlignment = stacked ? Alignment.center : Alignment.centerLeft;

    final ringWidget = RepaintBoundary(
      child: Padding(
        // The sparkles overhang the ring by up to 6 dp; this padding keeps them
        // inside the ring's own box instead of on the card's padding edge.
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          width: stacked ? null : WeeklyRingPainter.size,
          child: Center(
            child: Semantics(
              container: true,
              label: percent == null
                  ? '${reviewMoodLabel(mood)} week, no tasks'
                  : '$percent percent completed, ${reviewMoodLabel(mood)} week',
              excludeSemantics: true,
              child: SizedBox.square(
                dimension: WeeklyRingPainter.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: const ValueKey('weekly-ring'),
                        painter: WeeklyRingPainter(
                          fraction: (percent ?? 0) / 100 * ring,
                          track: tokens.outline,
                          color: moodColor,
                          glow: glow,
                          badge: mood == 1,
                          badgeProgress: faceOpacity,
                          badgeInk: tokens.surface,
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Fades in through the colour's alpha (no Opacity layer).
                          Transform.scale(
                            scale: 0.5 + 0.5 * faceScale,
                            child: MoodFace(
                              level: mood,
                              size: 36,
                              color: moodColor.withValues(alpha: faceOpacity),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            countText,
                            key: const ValueKey('weekly-reveal-count'),
                            style: reviewMonoStyle(context, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < sparkles; i++)
                      _Sparkle(
                        key: ValueKey('weekly-sparkle-$i'),
                        index: i,
                        progress: sparkle,
                        color: moodColor,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final text = Column(
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stacked) const SizedBox(height: AppSpacing.sm),
        _Step(
          key: const ValueKey('weekly-step-mood'),
          progress: step(WeeklyRevealTimeline.moodWord),
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) => Stack(
              alignment: blockAlignment,
              children: [...previous, ?current],
            ),
            child: Text(
              '${reviewMoodLabel(mood)} week',
              key: ValueKey('weekly-tier-$mood'),
              textAlign: textAlign,
              style: textTheme.titleLarge?.copyWith(
                color: moodColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Step(
          key: const ValueKey('weekly-step-message'),
          progress: step(WeeklyRevealTimeline.message),
          child: Text(
            weeklyMoodMessage(mood),
            textAlign: textAlign,
            style: textTheme.bodyMedium,
          ),
        ),
        if (widget.deltaText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _Step(
            key: const ValueKey('weekly-step-delta'),
            progress: step(WeeklyRevealTimeline.delta),
            child: Text(
              widget.deltaText!,
              textAlign: textAlign,
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ),
        ],
        if (widget.highlights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: wrapAlignment,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.highlights.length; i++)
                _Step(
                  key: ValueKey('weekly-highlight-$i'),
                  progress: step(
                    WeeklyRevealTimeline.chips +
                        WeeklyRevealTimeline.chipStep * i,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: WeeklyStyle.inset(context),
                      borderRadius: BorderRadius.circular(
                        WeeklyStyle.pillRadius,
                      ),
                    ),
                    child: Text(
                      widget.highlights[i],
                      style: textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (feeling.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _Step(
            key: const ValueKey('weekly-step-signoff'),
            progress: step(WeeklyRevealTimeline.signOff),
            child: Align(
              alignment: blockAlignment,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  '“$feeling”',
                  textAlign: textAlign,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final dots = WeeklyDotsRow(
      dots: widget.dots,
      currentFill: dotFill,
      reviewedCount: weeklyReviewedDotCount(
        widget.dots,
        currentSaved: t * total >= WeeklyRevealTimeline.dot,
      ),
      alignment: stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
    );

    switch (layout) {
      case _RevealLayout.stacked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ringWidget,
            text,
            const SizedBox(height: AppSpacing.md),
            dots,
          ],
        );
      case _RevealLayout.compact:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ringWidget,
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: text),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Same left axis as the ring (which has its own padding).
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: dots,
            ),
          ],
        );
    }
  }
}

/// Fades a line in and lifts it 4 px as [progress] goes 0 → 1.
class _Step extends StatelessWidget {
  const _Step({super.key, required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: progress,
    child: Transform.translate(
      offset: Offset(0, 4 * (1 - progress)),
      child: child,
    ),
  );
}

/// One plus-shaped sparkle around the ring (Great 1, Excellent 2,
/// Legendary 3). It twinkles in once and then stays.
class _Sparkle extends StatelessWidget {
  const _Sparkle({
    super.key,
    required this.index,
    required this.progress,
    required this.color,
  });

  final int index;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Keyframes: 0 % hidden at 0.3×, 45 % fully visible at 1.2× and 25°,
    // 100 % at 0.9 opacity, 1× and 0°.
    final double opacity;
    final double scale;
    final double turns;
    if (progress <= 0) {
      opacity = 0;
      scale = 0.3;
      turns = 0;
    } else if (progress < 0.45) {
      final k = progress / 0.45;
      opacity = k;
      scale = 0.3 + 0.9 * k;
      turns = 25 / 360 * k;
    } else {
      final k = (progress - 0.45) / 0.55;
      opacity = 1 - 0.1 * k;
      scale = 1.2 - 0.2 * k;
      turns = 25 / 360 * (1 - k);
    }
    final sparkle = Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: turns * 2 * math.pi,
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(painter: _SparklePainter(color)),
        ),
      ),
    );
    return switch (index) {
      0 => Positioned(top: -2, right: 4, width: 14, height: 14, child: sparkle),
      1 => Positioned(
        bottom: 12,
        left: -4,
        width: 11,
        height: 11,
        child: sparkle,
      ),
      _ => Positioned(top: 14, left: -6, width: 9, height: 9, child: sparkle),
    };
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 14;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(7 * s, 1 * s), Offset(7 * s, 13 * s), paint);
    canvas.drawLine(Offset(1 * s, 7 * s), Offset(13 * s, 7 * s), paint);
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => oldDelegate.color != color;
}

/// The completion ring: drawn in a 100 × 100 box (radius 40, stroke 6),
/// starting at the top, plus the Good check badge (circle r 10 at 84,84) and
/// an optional static glow (Excellent and Legendary; spec 3.7).
class WeeklyRingPainter extends CustomPainter {
  WeeklyRingPainter({
    required this.fraction,
    required this.track,
    required this.color,
    required this.glow,
    required this.badge,
    required this.badgeProgress,
    required this.badgeInk,
  });

  static const double size = 112;

  /// 0..1 of the circle to fill.
  final double fraction;
  final Color track;
  final Color color;
  final bool glow;
  final bool badge;

  /// 0..1: the badge appears with the face.
  final double badgeProgress;
  final Color badgeInk;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.scale(scale);
    const center = Offset(50, 50);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, 40, Paint.from(stroke)..color = track);
    if (fraction > 0) {
      final rect = Rect.fromCircle(center: center, radius: 40);
      final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
      if (glow) {
        canvas.drawArc(
          rect,
          -math.pi / 2,
          sweep,
          false,
          Paint.from(stroke)
            ..color = color.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint.from(stroke)..color = color,
      );
    }
    if (badge && badgeProgress > 0) {
      canvas.save();
      canvas.translate(84, 84);
      canvas.scale(0.5 + 0.5 * badgeProgress);
      canvas.translate(-84, -84);
      canvas.drawCircle(
        const Offset(84, 84),
        10,
        Paint()..color = color.withValues(alpha: badgeProgress),
      );
      canvas.drawPath(
        Path()
          ..moveTo(79.5, 84.3)
          ..relativeLineTo(3.2, 3.2)
          ..relativeLineTo(6, -6.6),
        Paint()
          ..color = badgeInk.withValues(alpha: badgeProgress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WeeklyRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.badge != badge ||
      oldDelegate.badgeProgress != badgeProgress ||
      oldDelegate.badgeInk != badgeInk;
}

/// Eight dots, oldest first, and `{n} of 8 weeks reviewed` (spec 3.10).
class WeeklyDotsRow extends StatelessWidget {
  const WeeklyDotsRow({
    super.key,
    required this.dots,
    required this.currentFill,
    required this.reviewedCount,
    this.alignment = CrossAxisAlignment.center,
  });

  /// Where the dots and their caption sit; centred unless a layout asks.
  final CrossAxisAlignment alignment;

  final List<WeeklyDot> dots;

  /// 0 = the current week's dot is dashed; 1 = filled with the accent.
  final double currentFill;
  final int reviewedCount;

  static const double size = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final colors = ReviewColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    Widget dot(WeeklyDot value) {
      switch (value.kind) {
        case WeeklyDotKind.gap:
          return CustomPaint(
            painter: DashedOutlinePainter(
              color: tokens.textMuted.withValues(alpha: 0.6),
              strokeWidth: 1.5,
              dash: 2.6,
              gap: 2.6,
              circle: true,
            ),
          );
        case WeeklyDotKind.reviewed:
          final mood = value.mood;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mood == null ? tokens.textMuted : colors.mood(mood),
            ),
          );
        case WeeklyDotKind.current:
          return Stack(
            fit: StackFit.expand,
            children: [
              if (currentFill < 1)
                CustomPaint(
                  painter: DashedOutlinePainter(
                    color: accent,
                    strokeWidth: 1.5,
                    dash: 2.6,
                    gap: 2.6,
                    circle: true,
                  ),
                ),
              if (currentFill > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: currentFill),
                  ),
                ),
            ],
          );
      }
    }

    return Column(
      crossAxisAlignment: alignment,
      children: [
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < dots.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: SizedBox.square(
                    key: ValueKey('weekly-dot-$i'),
                    dimension: size,
                    child: dot(dots[i]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          weeksReviewedLabel(reviewedCount),
          key: const ValueKey('weekly-dots-text'),
          style: weeklyCaptionStyle(context),
        ),
      ],
    );
  }
}
