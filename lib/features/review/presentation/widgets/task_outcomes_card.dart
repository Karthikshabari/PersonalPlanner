import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/review_draft.dart';
import '../../domain/review_plan_change.dart';
import '../../domain/review_reason_presets.dart';
import '../../domain/task_outcome.dart';
import '../../providers/review_draft_controller.dart';
import '../../providers/review_reason_presets_provider.dart';
import 'review_preset_editor.dart';
import 'review_snack_bar.dart';
import 'review_theme.dart';
import 'task_outcome_visuals.dart';

class TaskOutcomesCard extends ConsumerStatefulWidget {
  final DateTime date;
  final bool future;
  final AsyncValue<List<TaskOutcomeRow>> rows;
  final ReviewDraft draft;

  const TaskOutcomesCard({
    super.key,
    required this.date,
    required this.future,
    required this.rows,
    required this.draft,
  });

  @override
  ConsumerState<TaskOutcomesCard> createState() => _TaskOutcomesCardState();
}

class _TaskOutcomesCardState extends ConsumerState<TaskOutcomesCard> {
  bool _editingPresets = false;

  Future<void> _saveAsPreset(String text) async {
    final added = await ref
        .read(reviewReasonPresetsProvider.notifier)
        .saveAsPreset(text);
    if (added && mounted) showReviewSnackBar(context, 'Preset added');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final presets =
        ref.watch(reviewReasonPresetsProvider).value ?? const <String>[];
    final notifier = ref.read(reviewDraftProvider(widget.date).notifier);
    final rows = widget.rows.value;
    final missing = rows == null
        ? 0
        : rows
              .where(
                (row) =>
                    row.outcome != TaskOutcome.completed &&
                    (widget.draft.reasons[row.taskId]?.trim().isEmpty ?? true),
              )
              .length;

    final Widget body;
    if (widget.rows.hasError) {
      body = ErrorPanel(
        message: friendlyErrorMessage(widget.rows.error!),
        compact: true,
      );
    } else if (rows == null) {
      body = const LinearProgressIndicator();
    } else if (widget.future) {
      body = const Text('This day has not happened yet.');
    } else if (rows.isEmpty) {
      body = const Text('No tasks were planned for this day.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            TaskOutcomeRowView(
              key: ValueKey('review-outcome-row-${rows[i].taskId}'),
              row: rows[i],
              showDivider: i > 0,
              reason: widget.draft.reasons[rows[i].taskId] ?? '',
              hydrationVersion: widget.draft.hydrationVersion,
              presets: presets,
              enabled: widget.draft.hydrated,
              onReasonChanged: (text) =>
                  notifier.setReason(rows[i].taskId, text),
              onSaveAsPreset: _saveAsPreset,
            ),
        ],
      );
    }

    return AppSurface(
      key: const ValueKey('review-task-outcomes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text('Task outcomes', style: textTheme.titleMedium),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                children: [
                  if (!widget.future && rows != null && rows.isNotEmpty)
                    Text(
                      missing == 0
                          ? 'All reasons added'
                          : '$missing without a reason',
                      key: const ValueKey('review-reason-counter'),
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('review-edit-presets'),
                    onPressed: () =>
                        setState(() => _editingPresets = !_editingPresets),
                    child: Text(_editingPresets ? 'Done' : 'Edit presets'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_editingPresets) ...[
            const ReviewPresetEditor(),
            const SizedBox(height: AppSpacing.sm),
          ],
          body,
        ],
      ),
    );
  }
}

class TaskOutcomeRowView extends StatefulWidget {
  final TaskOutcomeRow row;
  final bool showDivider;
  final String reason;
  final int hydrationVersion;
  final List<String> presets;
  final bool enabled;
  final ValueChanged<String> onReasonChanged;
  final ValueChanged<String> onSaveAsPreset;

  const TaskOutcomeRowView({
    super.key,
    required this.row,
    required this.showDivider,
    required this.reason,
    required this.hydrationVersion,
    required this.presets,
    required this.enabled,
    required this.onReasonChanged,
    required this.onSaveAsPreset,
  });

  @override
  State<TaskOutcomeRowView> createState() => _TaskOutcomeRowViewState();
}

class _TaskOutcomeRowViewState extends State<TaskOutcomeRowView> {
  late final TextEditingController _reason = TextEditingController(
    text: widget.reason,
  );
  final _focus = FocusNode();

  /// Whether the "Noted" check fades in. True only when it appears because
  /// the user just left the field or tapped a preset chip; text that was
  /// already there (restored draft, saved review) shows it at once.
  bool _animateNoted = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && _reason.text.trim().isNotEmpty) {
      _animateNoted = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TaskOutcomeRowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hydrationVersion != widget.hydrationVersion &&
        _reason.text != widget.reason) {
      _reason.text = widget.reason;
      _animateNoted = false;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final row = widget.row;
    final mutedTabular = textTheme.bodySmall?.copyWith(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final meta =
        '${Duration(minutes: row.plannedMinutes).shortLabel} planned'
        '${row.trackedMinutes > 0 ? ' · ${Duration(minutes: row.trackedMinutes).shortLabel} tracked' : ''}';

    return Container(
      decoration: widget.showDivider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: tokens.outline)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            taskOutcomeIcon(row.outcome),
            size: 24,
            color: taskOutcomeColor(context, row.outcome),
            semanticLabel: row.outcome.label,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      DateFormat(
                        'HH:mm',
                      ).format(PlannerTimeZone.toPlannerLocal(row.startTime!)),
                      style: mutedTabular,
                    ),
                    if (row.planChange == null) ...[
                      Text(
                        row.title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TaskOutcomePill(outcome: row.outcome),
                    ],
                  ],
                ),
                if (row.planChange != null) ...[
                  PlanChangeBlock(
                    key: ValueKey('review-plan-change-${row.taskId}'),
                    change: row.planChange!,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TaskOutcomePill(outcome: row.outcome),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(meta, style: mutedTabular),
                if (row.outcome != TaskOutcome.completed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    label: 'Reason for ${row.title}',
                    child: TextField(
                      key: ValueKey('review-reason-${row.taskId}'),
                      controller: _reason,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      maxLines: 1,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(maxReviewReasonLength),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Why was this not done? (optional)',
                        // "Noted" whenever the field is not being edited and holds
                        // text. Nothing is persisted until "Save review".
                        suffixIcon: _NotedBadge(
                          visible:
                              !_focus.hasFocus &&
                              _reason.text.trim().isNotEmpty,
                          animate: _animateNoted,
                        ),
                        suffixIconConstraints: const BoxConstraints(),
                      ),
                      onChanged: widget.onReasonChanged,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _reason,
                    builder: (context, value, _) => Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final p in ReviewReasonPresets.chips(
                          widget.presets,
                        ))
                          ActionChip(
                            label: Text(p),
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.enabled
                                ? () {
                                    _reason.value = TextEditingValue(
                                      text: p,
                                      selection: TextSelection.collapsed(
                                        offset: p.length,
                                      ),
                                    );
                                    widget.onReasonChanged(p);
                                    _animateNoted = true;
                                    _focus.unfocus();
                                    setState(() {});
                                  }
                                : null,
                          ),
                        if (ReviewReasonPresets.canSaveAsPreset(
                          widget.presets,
                          value.text,
                        ))
                          TextButton(
                            key: ValueKey(
                              'review-save-as-preset-${row.taskId}',
                            ),
                            onPressed: () =>
                                widget.onSaveAsPreset(value.text.trim()),
                            child: const Text('+ Save as preset'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet "reason entered" confirmation at the end of the reason field, shown
/// while the field is not focused and has text. Fades and scales in when
/// [animate] is set (instantly with reduced motion or for text that was
/// already there); wording is "Noted" because nothing is persisted until
/// "Save review".
class _NotedBadge extends StatelessWidget {
  final bool visible;
  final bool animate;

  const _NotedBadge({required this.visible, required this.animate});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final teal = ReviewColors.of(context).success;
    return Semantics(
      label: 'Reason noted',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        key: const ValueKey('review-reason-noted'),
        tween: Tween(begin: 0, end: 1),
        duration: animate && !MediaQuery.disableAnimationsOf(context)
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 16, color: teal),
              const SizedBox(width: 4),
              Text(
                'Noted',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: teal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlanChangeBlock extends StatelessWidget {
  final ReviewPlanChange change;

  const PlanChangeBlock({super.key, required this.change});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.outline, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.oldValue,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  child: Icon(
                    planChangedIcon,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                ),
                TextSpan(
                  text: ' PLAN CHANGED',
                  style: reviewMonoStyle(context, fontSize: 10),
                ),
                if (change.reason != null)
                  TextSpan(
                    text: '  ${change.reason}',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            change.newValue,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
