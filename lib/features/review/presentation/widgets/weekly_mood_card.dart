import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import 'mood_face.dart';
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How was the week?', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Mood of the week',
            container: true,
            child: Row(
              children: [
                for (var level = 1; level <= 4; level++)
                  Expanded(
                    child: _WeeklyMoodOption(
                      level: level,
                      selected: selected == level,
                      enabled: enabled,
                      onChanged: onChanged,
                    ),
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
      HapticFeedback.lightImpact();
    }
    widget.onChanged(widget.level);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final level = widget.level;
    final selected = widget.selected;
    final moodColor = ReviewColors.of(context).mood(level);
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('weekly-mood-$level'),
            borderRadius: BorderRadius.circular(10),
            onTap: widget.enabled ? _pick : null,
            onFocusChange: (value) => setState(() => _focused = value),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: selected
                    ? moodColor.withValues(alpha: 0.14)
                    : Colors.transparent,
                border: Border.all(
                  color: _focused
                      ? tokens.focus
                      : selected
                      ? moodColor
                      : Colors.transparent,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  face,
                  const SizedBox(height: 4),
                  Text(
                    reviewMoodLabel(level),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? tokens.textPrimary : tokens.textMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
