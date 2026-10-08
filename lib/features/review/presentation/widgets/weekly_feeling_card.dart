import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/weekly_review_draft.dart';
import '../../domain/weekly_review_text.dart';
import 'review_theme.dart';

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
/// `n / 200` counter (spec 3.6).
class WeeklyFeelingCard extends StatefulWidget {
  const WeeklyFeelingCard({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final WeeklyReviewDraft draft;
  final ValueChanged<String> onChanged;

  @override
  State<WeeklyFeelingCard> createState() => _WeeklyFeelingCardState();
}

class _WeeklyFeelingCardState extends State<WeeklyFeelingCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.feeling,
  )..addListener(_onText);

  int _count = 0;

  @override
  void initState() {
    super.initState();
    _count = _controller.text.runes.length;
  }

  void _onText() {
    final count = _controller.text.runes.length;
    if (count != _count) setState(() => _count = count);
  }

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
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.draft.hydrated;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How did the week feel?', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in weeklyFeelingWords)
                ActionChip(
                  key: ValueKey('weekly-feeling-word-$word'),
                  label: Text(word),
                  onPressed: enabled ? () => _addWord(word) : null,
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
              decoration: const InputDecoration(
                hintText: 'A line or two about how this week felt.',
              ),
              onChanged: widget.onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_count / $maxWeeklyFeelingLength',
              key: const ValueKey('weekly-feeling-count'),
              style: reviewMonoStyle(context),
            ),
          ),
        ],
      ),
    );
  }
}
