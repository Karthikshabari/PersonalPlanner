import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';

/// Neutral reminder that the visible values are not stored yet. Muted colours
/// only: unsaved edits are not an error.
class ReviewUnsavedHint extends StatelessWidget {
  const ReviewUnsavedHint({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      label: 'Not saved yet',
      container: true,
      excludeSemantics: true,
      child: _HintRow(color: tokens.textMuted),
    );
  }
}

/// The same reminder floated at the bottom of the Daily screen, so it is in
/// view while a reason is typed far from the Save review button. It ignores
/// pointers and is hidden from semantics (the hint next to Save carries the
/// label).
class ReviewUnsavedPill extends StatelessWidget {
  const ReviewUnsavedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: tokens.surface,
            shape: StadiumBorder(side: BorderSide(color: tokens.outline)),
            shadows: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + 2,
            ),
            child: _HintRow(color: tokens.textMuted),
          ),
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Not saved yet',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
