import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_draft.dart';
import 'review_layout.dart';
import 'review_save_button.dart';
import 'review_theme.dart';
import 'review_unsaved_hint.dart';

/// The Daily review's Save bar, pinned under the scroll view: Save review /
/// Saved (cross-fading), the "Not saved yet" pill while the draft differs from
/// what is stored, and the Ctrl + Enter hint on wide desktop layouts. The same
/// look and states as the Weekly bar; it only knows the facts it shows.
class ReviewSaveBar extends StatelessWidget {
  const ReviewSaveBar({
    super.key,
    required this.status,
    required this.enabled,
    required this.differsFromSaved,
    required this.focusNode,
    required this.onSave,
    required this.showShortcutHint,
    this.blockedReason,
  });

  /// Already adjusted so "Saved" only shows while nothing differs from storage.
  final ReviewSaveStatus status;
  final bool enabled;

  /// Why Save is off for a reason the user can act on (a day that has not
  /// started); shown in place of the shortcut hint.
  final String? blockedReason;
  final bool differsFromSaved;
  final FocusNode focusNode;
  final VoidCallback onSave;
  final bool showShortcutHint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final modifier = showShortcutHint ? reviewSaveModifier() : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ReviewLayout.pagePadding,
            vertical: 10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ReviewLayout.maxContentWidth,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ReviewSaveButton(
                      status: status,
                      enabled: enabled,
                      focusNode: focusNode,
                      onPressed: onSave,
                      crossFadeLabel: true,
                    ),
                    if (differsFromSaved)
                      Semantics(
                        key: const ValueKey('review-unsaved-hint'),
                        label: 'Not saved yet',
                        container: true,
                        child: const ReviewUnsavedPill(),
                      ),
                    if (blockedReason != null)
                      Text(blockedReason!, style: weeklyCaptionStyle(context))
                    else if (modifier != null)
                      Text(
                        '$modifier + Enter',
                        style: weeklyCaptionStyle(context),
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
