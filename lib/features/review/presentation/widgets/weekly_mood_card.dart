import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import 'mood_face.dart';
import 'review_equal_grid.dart';
import 'review_header_body.dart';
import 'weekly_review_style.dart';
import 'review_theme.dart';

/// "How was the week?": four faces the user picks from (never detected).
/// Radio semantics, 44 dp minimum targets, a 240 ms face pop and a light
/// haptic on Android when a face is picked (spec 3.5).
class WeeklyMoodCard extends StatelessWidget {
  const WeeklyMoodCard({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    this.lastWeekHint,
  });

  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// `Last week: Great`, or null.
  final String? lastWeekHint;

  /// Room one tile needs for the longest label (semibold, as when selected)
  /// plus the tile's own padding and border.
  static double _minTileWidth(BuildContext context) =>
      measureWidestText(
        context,
        reviewMoodLabels,
        Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ) +
      2 * 2 + // tile horizontal padding
      2; // border

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: ReviewHeaderBody(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How was the week?', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
        // Centred in whatever height the row gives this card.
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Mood of the week',
              container: true,
              child: ReviewEqualGrid(
                minCellWidth: _minTileWidth(context),
                spacing: WeeklyStyle.space2,
                children: [
                  for (var level = 1; level <= 4; level++)
                    _WeeklyMoodOption(
                      level: level,
                      selected: selected == level,
                      enabled: enabled,
                      onChanged: onChanged,
                    ),
                ],
              ),
            ),
            if (lastWeekHint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                lastWeekHint!,
                key: const ValueKey('weekly-last-mood'),
                style: textTheme.bodySmall?.copyWith(
                  color: AppThemeTokens.of(context).textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeeklyMoodOption extends StatefulWidget {
  const _WeeklyMoodOption({
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final int level;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_WeeklyMoodOption> createState() => _WeeklyMoodOptionState();
}

class _WeeklyMoodOptionState extends State<_WeeklyMoodOption> {
  bool _focused = false;

  /// Bumped on every pick; a new value restarts the pop (0 = no pop yet).
  int _pops = 0;

  /// 1 → 1.28 → 1 over the pop.
  static double _popScale(double t) =>
      t < 0.5 ? 1 + 0.56 * t : 1.28 - 0.56 * (t - 0.5);

  void _pick() {
    if (widget.selected) return;
    if (!MediaQuery.disableAnimationsOf(context)) setState(() => _pops++);
    if (defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.selectionClick();
    }
    widget.onChanged(widget.level);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final level = widget.level;
    final selected = widget.selected;
    final moodColor = ReviewColors.of(context).mood(level);
    final radius = BorderRadius.circular(WeeklyStyle.insetRadius(context));
    Widget face = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? moodColor.withValues(alpha: 0.22)
            : Colors.transparent,
      ),
      child: MoodFace(level: level, size: 40),
    );
    if (_pops > 0) {
      face = TweenAnimationBuilder<double>(
        key: ValueKey('weekly-mood-pop-$level-$_pops'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        builder: (context, t, child) =>
            Transform.scale(scale: _popScale(t), child: child),
        child: face,
      );
    }
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: reviewMoodLabel(level),
      excludeSemantics: true,
      child: WeeklyPressScale(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('weekly-mood-$level'),
              borderRadius: radius,
              // Hover and pressed feedback for the unselected tiles.
              hoverColor: moodColor.withValues(alpha: 0.08),
              splashColor: moodColor.withValues(alpha: 0.16),
              highlightColor: moodColor.withValues(alpha: 0.12),
              onTap: widget.enabled ? _pick : null,
              onFocusChange: (value) => setState(() => _focused = value),
              child: AnimatedContainer(
                duration: WeeklyStyle.quickFor(context),
                curve: WeeklyStyle.curve,
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // Unselected tiles are a tonal inset (no border); the tier
                  // colour appears only when selected.
                  color: selected
                      ? moodColor.withValues(alpha: 0.14)
                      : WeeklyStyle.inset(context),
                  border: Border.all(
                    color: _focused
                        ? tokens.focus
                        : selected
                        ? moodColor
                        : Colors.transparent,
                    width: _focused ? 2 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        face,
                        const SizedBox(height: 4),
                        Text(
                          reviewMoodLabel(level),
                          maxLines: 1,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: selected
                                    ? tokens.textPrimary
                                    : tokens.textMuted,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                    // Selection does not rely on colour alone: a check fades in.
                    Positioned(
                      top: 0,
                      right: 2,
                      child: AnimatedOpacity(
                        opacity: selected ? 1 : 0,
                        duration: WeeklyStyle.quickFor(context),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: moodColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
