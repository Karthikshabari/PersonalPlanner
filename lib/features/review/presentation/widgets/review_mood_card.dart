import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_mood.dart';
import 'mood_face.dart';
import 'review_theme.dart';

class ReviewMoodCard extends StatelessWidget {
  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const ReviewMoodCard({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How was the day?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Mood of the day',
            container: true,
            child: Row(
              children: [
                for (var level = 1; level <= 4; level++)
                  Expanded(
                    child: _MoodOption(
                      level: level,
                      selected: selected == level,
                      enabled: enabled,
                      onChanged: onChanged,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodOption extends StatefulWidget {
  final int level;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _MoodOption({
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_MoodOption> createState() => _MoodOptionState();
}

class _MoodOptionState extends State<_MoodOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final level = widget.level;
    final selected = widget.selected;
    final moodColor = ReviewColors.of(context).mood(level);
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
            key: ValueKey('review-mood-$level'),
            borderRadius: BorderRadius.circular(10),
            onTap: widget.enabled
                ? () {
                    if (!selected) widget.onChanged(level);
                  }
                : null,
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? moodColor.withValues(alpha: 0.22)
                          : Colors.transparent,
                    ),
                    child: MoodFace(level: level, size: 40),
                  ),
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
