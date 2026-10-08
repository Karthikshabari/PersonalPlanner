import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_draft.dart';
import '../../domain/weekly_review_draft.dart';
import 'review_save_button.dart';
import 'review_theme.dart';
import 'review_unsaved_hint.dart';

/// The one Save bar shared by both Weekly sub-tabs, pinned under the scroll
/// view (WD16): Save review / Saved, the "Not saved yet" pill while the
/// draft differs from what is stored, and the Ctrl + Enter hint on wide
/// layouts (WD17).
class WeeklySaveBar extends StatelessWidget {
  const WeeklySaveBar({
    super.key,
    required this.draft,
    required this.focusNode,
    required this.onSave,
    required this.showShortcutHint,
  });

  final WeeklyReviewDraft draft;
  final FocusNode focusNode;
  final VoidCallback onSave;
  final bool showShortcutHint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ReviewSaveButton(
                      buttonKey: const ValueKey('weekly-save'),
                      // "Saved" is only true while nothing differs from storage.
                      status:
                          draft.differsFromSaved &&
                              draft.saveStatus == ReviewSaveStatus.saved
                          ? ReviewSaveStatus.idle
                          : draft.saveStatus,
                      enabled: draft.hydrated,
                      focusNode: focusNode,
                      onPressed: onSave,
                    ),
                    if (draft.differsFromSaved)
                      Semantics(
                        key: const ValueKey('weekly-unsaved-pill'),
                        label: 'Not saved yet',
                        container: true,
                        child: const ReviewUnsavedPill(),
                      ),
                    if (showShortcutHint)
                      Text('Ctrl + Enter', style: reviewMonoStyle(context)),
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
