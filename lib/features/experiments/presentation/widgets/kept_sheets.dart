import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../../analytics/providers/analytics_providers.dart';
import '../../domain/experiment_target_changes.dart';
import '../../domain/kept_copy.dart';
import '../../domain/kept_experiment.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_check_in_box.dart' show CodePointLimitingTextInputFormatter;
import 'experiment_ui.dart';
import 'kept_experiment_list.dart' show KeptRetiredEntry;
import 'kept_experiment_row.dart' show keptSpans;

const _failedToSave = 'That change was not saved. Try again.';
const _maxNoteRunes = 4000;

ButtonStyle _buttonStyle({
  required ExperimentStyles styles,
  Color? background,
  required Color foreground,
  BorderSide? side,
}) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  ),
  backgroundColor: WidgetStatePropertyAll(background),
  foregroundColor: WidgetStatePropertyAll(foreground),
  side: side == null ? null : WidgetStatePropertyAll(side),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
    ),
  ),
  textStyle: WidgetStatePropertyAll(
    styles.body.copyWith(fontWeight: FontWeight.w600),
  ),
);

/// Inline "Adjust weekly minimum" sheet. The draft lives in this widget's
/// state; only Save writes.
class KeptAdjustTargetSheet extends ConsumerStatefulWidget {
  const KeptAdjustTargetSheet({
    super.key,
    required this.view,
    required this.onClose,
  });

  final KeptExperimentView view;
  final VoidCallback onClose;

  @override
  ConsumerState<KeptAdjustTargetSheet> createState() =>
      _KeptAdjustTargetSheetState();
}

class _KeptAdjustTargetSheetState extends ConsumerState<KeptAdjustTargetSheet> {
  late int _weekday = keptClampTarget(widget.view.weekdayTargetMin);
  late int _weekend = keptClampTarget(widget.view.weekendTargetMin);
  bool _fromNextWeek = true;
  bool _busy = false;

  Future<void> _save() async {
    final view = widget.view;
    setState(() => _busy = true);
    try {
      await ref
          .read(experimentRepositoryProvider)
          .adjustKeptTarget(
            view.experimentId,
            weekdayTargetMin: _weekday,
            weekendTargetMin: _weekend,
            fromNextWeek: _fromNextWeek,
            today: isoDateString(ref.read(insightsNowProvider)),
            expectedRevision: view.revision,
          );
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showAppToast(context, _failedToSave);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final id = view.experimentId;
    final styles = ExperimentStyles.of(context);
    final weekdayStepper = _KeptStepper(
      id: id,
      part: 'weekday',
      label: keptWeekdaysLabel,
      value: _weekday,
      onChanged: (v) => setState(() => _weekday = v),
    );
    final weekendStepper = _KeptStepper(
      id: id,
      part: 'weekend',
      label: keptWeekendLabel,
      value: _weekend,
      onChanged: (v) => setState(() => _weekend = v),
    );
    return Column(
      key: ValueKey('kept-adjust-sheet-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(keptAdjustHeading, style: styles.sectionHeading),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  weekdayStepper,
                  const SizedBox(height: 14),
                  weekendStepper,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: weekdayStepper),
                const SizedBox(width: 14),
                Expanded(child: weekendStepper),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: styles.note,
            children: keptSpans(
              keptNewMinimumParts(_weekday, _weekend, formatMinutes),
              boldColor: styles.scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _choice(
              styles,
              key: ValueKey('kept-from-next-$id'),
              label: keptFromNextWeekLabel(view.nextWeekStart),
              selected: _fromNextWeek,
              onPressed: () => setState(() => _fromNextWeek = true),
            ),
            _choice(
              styles,
              key: ValueKey('kept-from-this-$id'),
              label: keptFromThisWeek,
              selected: !_fromNextWeek,
              onPressed: () => setState(() => _fromNextWeek = false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(keptEarlierWeeksNote, style: styles.note),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: ValueKey('kept-adjust-cancel-$id'),
                style: _buttonStyle(
                  styles: styles,
                  background: styles.strip,
                  foreground: styles.scheme.onSurface,
                ),
                onPressed: _busy ? null : widget.onClose,
                child: const Text(keptCancel),
              ),
              FilledButton(
                key: ValueKey('kept-adjust-save-$id'),
                style: _buttonStyle(
                  styles: styles,
                  background: styles.accent,
                  foreground: styles.scheme.onPrimary,
                ),
                onPressed: _busy ? null : _save,
                child: const Text(keptSave),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choice(
    ExperimentStyles styles, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: OutlinedButton(
      key: key,
      style: _buttonStyle(
        styles: styles,
        background: selected ? styles.tint(styles.accent) : null,
        foreground: selected ? styles.accentText : styles.scheme.onSurface,
        side: BorderSide(
          color: selected ? styles.accent : styles.scheme.outlineVariant,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

/// A label above a `−  75m  +` control that moves in steps of 15 minutes.
class _KeptStepper extends StatelessWidget {
  const _KeptStepper({
    required this.id,
    required this.part,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String id;

  /// `weekday` or `weekend`, used in the keys.
  final String part;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final canLess = value > keptTargetMinMinutes;
    final canMore = value < keptTargetMaxMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: styles.label),
        const SizedBox(height: 6),
        Semantics(
          label: '$label: ${value}m',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: styles.field,
                borderRadius: BorderRadius.circular(
                  ExperimentStyles.innerRadius,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StepButton(
                      key: ValueKey('kept-stepper-$part-$id-minus'),
                      semanticsLabel: keptStepperLess,
                      glyph: '−',
                      color: styles.scheme.onSurface,
                      disabledColor: styles.muted,
                      onTap: canLess
                          ? () => onChanged(keptStepDown(value))
                          : null,
                    ),
                    Text('${value}m', style: styles.statValue),
                    _StepButton(
                      key: ValueKey('kept-stepper-$part-$id-plus'),
                      semanticsLabel: keptStepperMore,
                      glyph: '+',
                      color: styles.scheme.onSurface,
                      disabledColor: styles.muted,
                      onTap: canMore
                          ? () => onChanged(keptStepUp(value))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.semanticsLabel,
    required this.glyph,
    required this.color,
    required this.disabledColor,
    required this.onTap,
  });

  final String semanticsLabel;
  final String glyph;
  final Color color;
  final Color disabledColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: semanticsLabel,
    excludeSemantics: true,
    child: SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            glyph,
            style: TextStyle(
              fontSize: 20,
              color: onTap == null ? disabledColor : color,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Inline "Retire {name}?" sheet with an optional note.
class KeptRetireSheet extends ConsumerStatefulWidget {
  const KeptRetireSheet({
    super.key,
    required this.view,
    required this.onClose,
    required this.onRetired,
  });

  final KeptExperimentView view;
  final VoidCallback onClose;
  final void Function(KeptRetiredEntry entry) onRetired;

  @override
  ConsumerState<KeptRetireSheet> createState() => _KeptRetireSheetState();
}

class _KeptRetireSheetState extends ConsumerState<KeptRetireSheet> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _retire() async {
    final view = widget.view;
    final note = _note.text;
    setState(() => _busy = true);
    try {
      final retired = await ref
          .read(experimentRepositoryProvider)
          .retireKeptExperiment(
            view.experimentId,
            note: note,
            expectedRevision: view.revision,
          );
      widget.onRetired((
        experimentId: view.experimentId,
        name: view.name,
        noteSaved: note.trim().isNotEmpty,
        keptSince: view.keptSince,
        revision: retired.revision,
      ));
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showAppToast(context, _failedToSave);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final id = view.experimentId;
    final styles = ExperimentStyles.of(context);
    return Column(
      key: ValueKey('kept-retire-sheet-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(keptRetireHeading(view.name), style: styles.sectionHeading),
        const SizedBox(height: 14),
        Text(keptRetireExplanation, style: styles.note),
        const SizedBox(height: 14),
        Text(keptRetireNoteLabel, style: styles.label),
        const SizedBox(height: 6),
        Semantics(
          label: keptRetireNoteLabel,
          child: TextField(
            key: ValueKey('kept-retire-note-$id'),
            controller: _note,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            style: styles.body,
            inputFormatters: const [
              CodePointLimitingTextInputFormatter(_maxNoteRunes),
            ],
            decoration: InputDecoration(
              filled: true,
              fillColor: styles.field,
              hintText: keptRetireNoteHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  ExperimentStyles.innerRadius,
                ),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: ValueKey('kept-retire-cancel-$id'),
                style: _buttonStyle(
                  styles: styles,
                  background: styles.strip,
                  foreground: styles.scheme.onSurface,
                ),
                onPressed: _busy ? null : widget.onClose,
                child: const Text(keptCancel),
              ),
              FilledButton(
                key: ValueKey('kept-retire-submit-$id'),
                style: _buttonStyle(
                  styles: styles,
                  background: styles.accent,
                  foreground: styles.scheme.onPrimary,
                ),
                onPressed: _busy ? null : _retire,
                child: const Text(keptRetireButton),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
