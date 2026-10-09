import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/weekly_review_draft.dart';
import '../../domain/weekly_feeling_presets.dart';
import '../../domain/weekly_review_text.dart';
import '../../providers/weekly_feeling_presets_provider.dart';
import 'review_equal_grid.dart';
import 'review_theme.dart';
import 'weekly_feeling_preset_editor.dart';
import 'weekly_review_style.dart';

/// Limits text to [maxRunes] Unicode code points, the unit the feeling is
/// stored and validated in (WD7). Longer input is clipped.
class RuneLimitingTextInputFormatter extends TextInputFormatter {
  const RuneLimitingTextInputFormatter(this.maxRunes);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxRunes) return newValue;
    final clipped = String.fromCharCodes(newValue.text.runes.take(maxRunes));
    return TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }
}

/// "How did the week feel?": a short text with feeling-word chips and an
/// `n / 200` counter (spec 3.6). The four words are user-defined
/// ([weeklyFeelingPresetsProvider]); they only append text, so a review saved
/// with an older word (Energised, Busy) keeps its text as written.
class WeeklyFeelingCard extends ConsumerStatefulWidget {
  const WeeklyFeelingCard({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final WeeklyReviewDraft draft;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<WeeklyFeelingCard> createState() => _WeeklyFeelingCardState();
}

class _WeeklyFeelingCardState extends ConsumerState<WeeklyFeelingCard> {
  bool _editingPresets = false;

  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.feeling,
  );

  @override
  void didUpdateWidget(WeeklyFeelingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.hydrationVersion != widget.draft.hydrationVersion &&
        _controller.text != widget.draft.feeling) {
      _controller.text = widget.draft.feeling;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addWord(String word) {
    final next = appendFeelingWord(_controller.text, word);
    if (next == null) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.selectionClick();
    }
    widget.onChanged(next);
  }

  /// A 2 dp ring in the focus token while the control has keyboard focus.
  static WidgetStateBorderSide _focusRing(
    AppThemeTokens tokens, {
    bool chip = false,
  }) => WidgetStateBorderSide.resolveWith((states) {
    if (states.contains(WidgetState.focused)) {
      return BorderSide(color: tokens.focus, width: 2);
    }
    return BorderSide.none;
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = AppThemeTokens.of(context);
    final enabled = widget.draft.hydrated;
    final words =
        ref.watch(weeklyFeelingPresetsProvider).value ??
        defaultWeeklyFeelingPresets;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'How did the week feel?',
                  style: textTheme.titleMedium,
                ),
              ),
              Semantics(
                button: true,
                expanded: _editingPresets,
                label: _editingPresets
                    ? 'Done editing feeling presets'
                    : 'Edit feeling presets',
                excludeSemantics: true,
                child: TextButton(
                  key: const ValueKey('weekly-feeling-edit-presets'),
                  style: TextButton.styleFrom(
                    // No side padding on the right, so the label lines up
                    // with the card's content edge; the target stays 48 dp.
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    alignment: Alignment.centerRight,
                  ).copyWith(side: _focusRing(tokens)),
                  onPressed: () =>
                      setState(() => _editingPresets = !_editingPresets),
                  child: Text(_editingPresets ? 'Done' : 'Edit presets'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // The card's height follows its content: it grows when the editor
          // opens and shrinks back on Done.
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: _editingPresets
                ? const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: WeeklyFeelingPresetEditor(),
                  )
                : const SizedBox(width: double.infinity),
          ),
          ReviewEqualGrid(
            // A chip needs its label plus the chip's own padding.
            minCellWidth:
                measureWidestText(
                  context,
                  words,
                  Theme.of(context).textTheme.labelLarge,
                ) +
                2 * AppSpacing.lg,
            spacing: AppSpacing.sm,
            children: [
              for (final word in words)
                Tooltip(
                  message: word,
                  child: WeeklyPressScale(
                    child: ActionChip(
                      key: ValueKey('weekly-feeling-word-$word'),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      side: _focusRing(tokens, chip: true),
                      // Tonal fill, lighter on hover; no border.
                      color: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.hovered)
                            ? WeeklyStyle.insetHover(context)
                            : WeeklyStyle.inset(context),
                      ),
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      onPressed: enabled ? () => _addWord(word) : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'How did the week feel?',
            child: TextField(
              key: const ValueKey('weekly-feeling'),
              controller: _controller,
              enabled: enabled,
              minLines: 2,
              maxLines: 4,
              inputFormatters: const [
                RuneLimitingTextInputFormatter(maxWeeklyFeelingLength),
              ],
              decoration: WeeklyStyle.fieldDecoration(
                context,
                hintText: 'A line or two about how this week felt.',
              ),
              onChanged: widget.onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            // Typing rebuilds only this counter and the field itself.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => Text(
                '${value.text.runes.length} / $maxWeeklyFeelingLength',
                key: const ValueKey('weekly-feeling-count'),
                style: weeklyCaptionStyle(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
