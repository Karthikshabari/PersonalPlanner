import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_draft.dart';
import '../../domain/weekly_review_draft.dart';
import 'review_save_button.dart';

/// The one Save bar shared by both Weekly sub-tabs, pinned under the scroll
/// view (WD16).
class WeeklySaveBar extends StatelessWidget {
  const WeeklySaveBar({
    super.key,
    required this.draft,
    required this.focusNode,
    required this.onSave,
  });

  final WeeklyReviewDraft draft;
  final FocusNode focusNode;
  final VoidCallback onSave;

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
                child: ReviewSaveButton(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
