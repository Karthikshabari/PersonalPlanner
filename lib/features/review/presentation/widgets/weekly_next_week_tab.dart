import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/weekly_review_draft.dart';
import '../../domain/weekly_review_text.dart';
import 'weekly_note_line.dart';

/// The "Next week (optional)" sub-tab: one short note that opens next week's
/// review, with starter chips, the week's top blocker and a preview
/// (spec 3.11).
class WeeklyNextWeekTab extends StatefulWidget {
  const WeeklyNextWeekTab({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.blockerLine,
  });

  final WeeklyReviewDraft draft;
  final ValueChanged<String> onChanged;

  /// `Most common blocker this week: … (n times).` or the no-blocker line.
  final String blockerLine;

  @override
  State<WeeklyNextWeekTab> createState() => _WeeklyNextWeekTabState();
}

class _WeeklyNextWeekTabState extends State<WeeklyNextWeekTab> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.note,
  )..addListener(_onText);
  final _focus = FocusNode(debugLabel: 'weekly-note');
  late String _preview = widget.draft.note.trim();

  void _onText() {
    final preview = _controller.text.trim();
    if (preview != _preview) setState(() => _preview = preview);
  }

  @override
  void didUpdateWidget(WeeklyNextWeekTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.hydrationVersion != widget.draft.hydrationVersion &&
        _controller.text != widget.draft.note) {
      _controller.text = widget.draft.note;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _applyStarter(String insert) {
    final next = applyNoteStarter(_controller.text, insert);
    if (next == null) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged(next);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.draft.hydrated;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('A note for next week', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Optional. It appears at the top of next week's review.",
              style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < weeklyNoteStarters.length; i++)
                  ActionChip(
                    key: ValueKey('weekly-starter-$i'),
                    label: Text(weeklyNoteStarters[i].label),
                    onPressed: enabled
                        ? () => _applyStarter(weeklyNoteStarters[i].insert)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'A note for next week',
              child: TextField(
                key: const ValueKey('weekly-note'),
                controller: _controller,
                focusNode: _focus,
                enabled: enabled,
                maxLines: 1,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(maxWeeklyNoteLength),
                ],
                onChanged: widget.onChanged,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.blockerLine,
              key: const ValueKey('weekly-blocker'),
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            WeeklyNoteLine(
              key: const ValueKey('weekly-next-preview'),
              heading: 'How it will look next week',
              note: _preview,
              emptyText:
                  "Nothing set. Next week's review will start without a note.",
            ),
          ],
        ),
      ),
    );
  }
}
