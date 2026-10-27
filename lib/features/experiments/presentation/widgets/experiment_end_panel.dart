import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/experiment.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_check_in_box.dart' show CodePointLimitingTextInputFormatter;
import 'experiment_ui.dart';

const _reasonLabel = 'Why are you extending? (required)';
const _learnedLabel = 'What did you learn?';
const _maxReasonRunes = 500;
const _maxNoteRunes = 4000;
const _extendOptions = [7, 14, 30];

/// "The end date has arrived" (R25): shown for a running experiment on and
/// after its end date. Extend needs a reason; Conclude takes an optional note.
/// Both close nothing and show no success toast: the card updates in place
/// (ED32).
class ExperimentEndPanel extends ConsumerStatefulWidget {
  const ExperimentEndPanel({super.key, required this.experiment});

  final Experiment experiment;

  @override
  ConsumerState<ExperimentEndPanel> createState() => _ExperimentEndPanelState();
}

class _ExperimentEndPanelState extends ConsumerState<ExperimentEndPanel> {
  final _reason = TextEditingController();
  final _note = TextEditingController();
  int _days = 14;
  ExperimentOutcome? _outcome;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(String today) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final today = isoDateString(ref.read(insightsNowProvider));
      await action(today);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'That change was not saved. Try again.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _extend() => _run((today) async {
    await ref
        .read(experimentRepositoryProvider)
        .extendExperiment(
          widget.experiment.id,
          days: _days,
          reason: _reason.text,
          today: today,
          expectedRevision: widget.experiment.revision,
        );
    if (mounted) _reason.clear();
  });

  Future<void> _conclude(ExperimentOutcome outcome) => _run((today) async {
    final concluded = ref.read(experimentConcludedProvider.notifier);
    final ended = ref.read(experimentEndedProvider.notifier);
    final done = await ref
        .read(experimentRepositoryProvider)
        .concludeExperiment(
          widget.experiment.id,
          outcome: outcome,
          note: _note.text,
          today: today,
          expectedRevision: widget.experiment.revision,
        );
    if (ended.state?.experimentId == done.id) ended.state = null;
    concluded.state = (experimentId: done.id, revision: done.revision);
  });

  @override
  Widget build(BuildContext context) {
    final id = widget.experiment.id;
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );
    final canExtend = !_busy && _reason.text.trim().isNotEmpty;
    final outcome = _outcome;

    return AppSurface(
      key: ValueKey('end-panel-$id'),
      color: ExperimentStyles.of(context).strip,
      outlined: false,
      borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('The end date has arrived', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You can extend the experiment, but you have to say why. '
            'Or conclude it and write what you learned.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final days in _extendOptions)
                ButtonSegment(
                  value: days,
                  label: Text(
                    '$days more days',
                    key: ValueKey('extend-days-$days'),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            selected: {_days},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _days = selection.first),
          ),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(child: Text(_reasonLabel, style: labelStyle)),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _reasonLabel,
            child: TextField(
              key: ValueKey('extend-reason-$id'),
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              inputFormatters: const [
                CodePointLimitingTextInputFormatter(_maxReasonRunes),
              ],
              decoration: const InputDecoration(
                hintText: 'For example: I missed a week while travelling.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: ValueKey('extend-submit-$id'),
              onPressed: canExtend ? _extend : null,
              child: const Text('Extend'),
            ),
          ),
          const Divider(height: AppSpacing.xxl),
          SegmentedButton<ExperimentOutcome>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final outcome in ExperimentOutcome.values)
                ButtonSegment(
                  value: outcome,
                  label: Text(
                    outcome.label,
                    key: ValueKey('conclude-outcome-${outcome.dbValue}'),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            selected: {?_outcome},
            onSelectionChanged: _busy
                ? null
                : (selection) =>
                      setState(() => _outcome = selection.firstOrNull),
          ),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(child: Text(_learnedLabel, style: labelStyle)),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _learnedLabel,
            child: TextField(
              key: ValueKey('conclude-note-$id'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              inputFormatters: const [
                CodePointLimitingTextInputFormatter(_maxNoteRunes),
              ],
              decoration: const InputDecoration(
                hintText:
                    'For example: I like how close to the machine it feels.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: ValueKey('conclude-submit-$id'),
              onPressed: _busy || outcome == null
                  ? null
                  : () => _conclude(outcome),
              child: const Text('Conclude'),
            ),
          ),
        ],
      ),
    );
  }
}
