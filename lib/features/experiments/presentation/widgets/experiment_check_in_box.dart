import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_ui.dart';

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

const _dateLabel = 'Which day is this for?';
const _dateHelper = 'Missed days stay here until you write them.';
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
    final styles = ExperimentStyles.of(context);
    final date = _effectiveDate;
    final canSave = !_saving && _note.text.trim().isNotEmpty;
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
          borderSide: side,
        );

    return Column(
      key: ValueKey('checkin-box-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            Text('Share your experience', style: styles.sectionHeading),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (widget.missedCount > 0)
                  ExperimentChip(
                    key: ValueKey('checkin-missed-$id'),
                    text: '${widget.missedCount} missed',
                    color: styles.amber,
                  ),
                if (widget.dueToday)
                  ExperimentChip(
                    key: ValueKey('checkin-due-today-$id'),
                    text: '1 due today',
                    color: styles.accent,
                    textColor: styles.accentText,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(child: Text(_dateLabel, style: styles.label)),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: '$_dateLabel $_dateHelper',
          child: InputDecorator(
            decoration: InputDecoration(
              filled: true,
              fillColor: styles.field,
              border: border(),
              enabledBorder: border(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: ValueKey('checkin-date-$id'),
                value: date,
                isExpanded: true,
                itemHeight: 48,
                style: styles.body,
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
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(child: Text(_dateHelper, style: styles.caption)),
        const SizedBox(height: AppSpacing.lg),
        ExcludeSemantics(child: Text(_noteLabel, style: styles.label)),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: _noteLabel,
          child: TextField(
            key: ValueKey('checkin-note-$id'),
            controller: _note,
            minLines: 3,
            maxLines: 6,
            style: styles.body,
            keyboardType: TextInputType.multiline,
            inputFormatters: const [
              CodePointLimitingTextInputFormatter(_maxNoteRunes),
            ],
            decoration: InputDecoration(
              hintText: 'A few lines is enough.',
              filled: true,
              fillColor: styles.field,
              border: border(),
              enabledBorder: border(),
              focusedBorder: border(
                BorderSide(color: styles.accent, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: ValueKey('checkin-save-$id'),
            style: FilledButton.styleFrom(
              backgroundColor: styles.accent,
              foregroundColor: styles.scheme.onPrimary,
              disabledBackgroundColor: styles.scheme.surfaceContainerHighest,
              disabledForegroundColor: styles.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ExperimentStyles.innerRadius,
                ),
              ),
            ),
            onPressed: canSave ? () => _save(date) : null,
            child: Text(
              'Save check-in for ${_buttonDate(date)}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
