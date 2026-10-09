import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../providers/experiment_providers.dart';

/// Limits text to [maxRunes] Unicode code points, the unit the experiment
/// texts are validated in (ED9), and never splits a grapheme cluster, so an
/// emoji sequence is kept whole or dropped whole. Flutter's `maxLength` counts
/// grapheme clusters instead and would let such a sequence exceed the limit.
class CodePointLimitingTextInputFormatter extends TextInputFormatter {
  const CodePointLimitingTextInputFormatter(this.maxRunes);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxRunes) return newValue;
    final kept = StringBuffer();
    var runes = 0;
    for (final cluster in newValue.text.characters) {
      final clusterRunes = cluster.runes.length;
      if (runes + clusterRunes > maxRunes) break;
      kept.write(cluster);
      runes += clusterRunes;
    }
    final text = kept.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

const _dateLabel =
    'Which day is this for? Missed days stay here until you write them.';
const _noteLabel =
    'How is it going? What did you notice, and is it what you expected?';
const _maxNoteRunes = 4000;

String _dropdownDate(String isoDate) =>
    DateFormat('EEE MMM d').format(parseIsoDate(isoDate));

String _buttonDate(String isoDate) =>
    DateFormat('MMM d').format(parseIsoDate(isoDate));

/// "Share your experience" (R21): shown only while the experiment is running
/// and at least one slot is pending. It lists the pending dates, takes one
/// required note and writes the check-in for the chosen slot.
class ExperimentCheckInBox extends ConsumerStatefulWidget {
  const ExperimentCheckInBox({
    super.key,
    required this.experimentId,
    required this.pendingDates,
    required this.missedCount,
    required this.dueToday,
  });

  final String experimentId;

  /// Pending slot dates, earliest first (`yyyy-MM-dd`).
  final List<String> pendingDates;
  final int missedCount;
  final bool dueToday;

  @override
  ConsumerState<ExperimentCheckInBox> createState() =>
      _ExperimentCheckInBoxState();
}

class _ExperimentCheckInBoxState extends ConsumerState<ExperimentCheckInBox> {
  final _note = TextEditingController();
  String? _selected;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The chosen date while it is still pending, otherwise the latest one.
  String get _effectiveDate {
    final pending = widget.pendingDates;
    final selected = _selected;
    return selected != null && pending.contains(selected)
        ? selected
        : pending.last;
  }

  Future<void> _save(String slotDate) async {
    setState(() => _saving = true);
    var saved = false;
    try {
      final today = isoDateString(ref.read(insightsNowProvider));
      await ref
          .read(experimentRepositoryProvider)
          .saveCheckIn(
            experimentId: widget.experimentId,
            slotDate: slotDate,
            note: _note.text,
            today: today,
          );
      saved = true;
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'The check-in was not saved. Try again.');
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) {
        _note.clear();
        _selected = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingDates;
    if (pending.isEmpty) return const SizedBox.shrink();
    final id = widget.experimentId;
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final date = _effectiveDate;
    final canSave = !_saving && _note.text.trim().isNotEmpty;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );

    return AppSurface(
      key: ValueKey('checkin-box-$id'),
      color: tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Share your experience', style: theme.textTheme.titleSmall),
              if (widget.missedCount > 0)
                _CountChip(
                  key: ValueKey('checkin-missed-$id'),
                  text: '${widget.missedCount} missed',
                ),
              if (widget.dueToday)
                _CountChip(
                  key: ValueKey('checkin-due-today-$id'),
                  text: '1 due today',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(child: Text(_dateLabel, style: labelStyle)),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _dateLabel,
            child: InputDecorator(
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('checkin-date-$id'),
                  value: date,
                  isExpanded: true,
                  items: [
                    for (final d in pending)
                      DropdownMenuItem(value: d, child: Text(_dropdownDate(d))),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _selected = value),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(child: Text(_noteLabel, style: labelStyle)),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _noteLabel,
            child: TextField(
              key: ValueKey('checkin-note-$id'),
              controller: _note,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              inputFormatters: const [
                CodePointLimitingTextInputFormatter(_maxNoteRunes),
              ],
              decoration: const InputDecoration(
                hintText: 'A few lines is enough.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: ValueKey('checkin-save-$id'),
              onPressed: canSave ? () => _save(date) : null,
              child: Text(
                'Save check-in for ${_buttonDate(date)}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet, neutral count label (never red).
class _CountChip extends StatelessWidget {
  const _CountChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
