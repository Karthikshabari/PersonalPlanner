import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_mood.dart';
import 'mood_face.dart';
import 'review_equal_grid.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// One rating tile of "How was the day / week?": a tonal inset with the tier
/// face and label, hover and pressed feedback, a tier-coloured fill, border
/// and check when selected, and a 2 dp focus ring. Radio semantics, 44 dp
/// minimum target, a 240 ms face pop and a selection haptic on Android.
///
/// Moved out of the Weekly mood card so Daily and Weekly share one tile; the
/// keys are `<keyPrefix>-<level>` (and `<keyPrefix>-pop-<level>-<n>`).
class ReviewMoodTile extends StatefulWidget {
  const ReviewMoodTile({
    super.key,
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.keyPrefix,
    this.selectedScale = 1.0,
  });

  final int level;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// `weekly-mood` or `review-mood`.
  final String keyPrefix;

  /// Scale of the selected tile (1.0 = none).
  final double selectedScale;

  /// Room one tile needs for the longest label (semibold, as when selected)
  /// plus the tile's own padding and border.
  static double minWidth(BuildContext context) =>
      measureWidestText(
        context,
        reviewMoodLabels,
        Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ) +
      2 * 2 + // tile horizontal padding
      2; // border

  @override
  State<ReviewMoodTile> createState() => _ReviewMoodTileState();
}

class _ReviewMoodTileState extends State<ReviewMoodTile> {
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
        key: ValueKey('${widget.keyPrefix}-pop-$level-$_pops'),
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
        selected: selected,
        selectedScale: widget.selectedScale,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('${widget.keyPrefix}-$level'),
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
