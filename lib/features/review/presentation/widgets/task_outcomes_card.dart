import 'package:flutter/foundation.dart';
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
import '../../domain/review_plan_change.dart';
import '../../domain/review_reason_presets.dart';
import '../../domain/task_outcome.dart';
import '../../providers/review_draft_controller.dart';
import '../../providers/review_reason_presets_provider.dart';
import 'review_animated_size.dart';
import 'review_cell_grid.dart';
import 'review_equal_grid.dart';
import 'review_preset_chip.dart';
import 'review_preset_editor.dart';
import 'review_snack_bar.dart';
import 'review_theme.dart';
import 'task_outcome_visuals.dart';
import 'weekly_review_style.dart';

/// Tasks that can take a reason (not Completed) and have none typed yet.
int _missingReasons(List<TaskOutcomeRow> rows, Map<String, String> reasons) =>
    rows
        .where(
          (row) =>
              row.outcome != TaskOutcome.completed &&
              (reasons[row.taskId]?.trim().isEmpty ?? true),
        )
        .length;

/// "Task outcomes": a header (title, reasons status, Edit presets) and one row
/// per task. The card itself listens to nothing that changes while typing;
/// the status pill and every row listen to their own slice of the draft.
class TaskOutcomesCard extends ConsumerStatefulWidget {
  final DateTime date;
  final bool future;
  final AsyncValue<List<TaskOutcomeRow>> rows;

  const TaskOutcomesCard({
    super.key,
    required this.date,
    required this.future,
    required this.rows,
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

  /// Title and status on the left, "Edit presets" at the right end of the same
  /// row. When the title would be squeezed (a narrow card or a large text
  /// scale) the button drops to its own right-aligned line instead; the status
  /// wraps under the title either way.
  Widget _buildHeader(
    BuildContext context,
    AppThemeTokens tokens,
    TextTheme textTheme,
    List<TaskOutcomeRow>? rows,
  ) {
    final titleRow = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Task outcomes', style: textTheme.titleMedium),
        if (!widget.future && rows != null && rows.isNotEmpty)
          _ReasonStatusPill(date: widget.date, rows: rows),
      ],
    );
    final button = Semantics(
      button: true,
      expanded: _editingPresets,
      label: _editingPresets
          ? 'Done editing reason presets'
          : 'Edit reason presets',
      excludeSemantics: true,
      child: TextButton(
        key: const ValueKey('review-edit-presets'),
        style: TextButton.styleFrom(
          // No padding on the right, so the label lines up with the card's
          // content edge; the target stays 48 dp.
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          alignment: Alignment.centerRight,
        ).copyWith(side: reviewFocusRing(tokens)),
        onPressed: () => setState(() => _editingPresets = !_editingPresets),
        child: Text(_editingPresets ? 'Done' : 'Edit presets'),
      ),
    );
    final titleWidth = measureWidestText(context, const [
      'Task outcomes',
    ], textTheme.titleMedium);
    final buttonWidth =
        measureWidestText(context, const [
          'Edit presets',
          'Done',
        ], textTheme.labelLarge) +
        AppSpacing.sm +
        AppSpacing.lg;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth - buttonWidth - AppSpacing.sm >= titleWidth;
        if (sideBySide) {
          return Row(
            children: [
              Expanded(child: titleRow),
              button,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleRow,
            Align(alignment: Alignment.centerRight, child: button),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final presets =
        ref.watch(reviewReasonPresetsProvider).value ?? const <String>[];
    final rows = widget.rows.value;

    final Widget body;
    if (widget.rows.hasError) {
      body = ErrorPanel(
        message: friendlyErrorMessage(widget.rows.error!),
        compact: true,
      );
    } else if (rows == null) {
      body = const LinearProgressIndicator();
    } else if (widget.future) {
      body = Text(
        'This day has not happened yet.',
        style: textTheme.bodyMedium,
      );
    } else if (rows.isEmpty) {
      body = Text(
        'No tasks to review for this day',
        style: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            TaskOutcomeRowView(
              key: ValueKey('review-outcome-row-${rows[i].taskId}'),
              date: widget.date,
              row: rows[i],
              showDivider: i > 0,
              presets: presets,
              onSaveAsPreset: _saveAsPreset,
            ),
        ],
      );
    }

    return AppSurface(
      key: const ValueKey('review-task-outcomes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, tokens, textTheme, rows),
          const SizedBox(height: WeeklyStyle.titleGap),
          // The card's height follows its content: it grows when the editor
          // opens and shrinks back on Done.
          ReviewAnimatedSize(
            child: _editingPresets
                ? const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ReviewPresetEditor(grid: true),
                  )
                : const SizedBox(width: double.infinity),
          ),
          body,
        ],
      ),
    );
  }
}

/// "All reasons added" / "2 without a reason" as a small pill beside the
/// title. Listens to the count only, so typing rebuilds it once per change of
/// the count, not per keystroke. Neutral when reasons are missing (an
/// unfinished task is not an error); the success tint once all are noted.
class _ReasonStatusPill extends ConsumerWidget {
  const _ReasonStatusPill({required this.date, required this.rows});

  final DateTime date;
  final List<TaskOutcomeRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(
      reviewDraftProvider(date)
          .select((draft) => _missingReasons(rows, draft.reasons)),
    );
    final tokens = AppThemeTokens.of(context);
    final success = ReviewColors.of(context).success;
    final done = missing == 0;
    final color = done ? success : tokens.textMuted;
    return AnimatedContainer(
      duration: WeeklyStyle.quickFor(context),
      curve: WeeklyStyle.curve,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: done
            ? Color.alphaBlend(success.withValues(alpha: 0.12), tokens.surface)
            : WeeklyStyle.inset(context),
        borderRadius: BorderRadius.circular(WeeklyStyle.pillRadius),
      ),
      child: Text(
        done ? 'All reasons added' : '$missing without a reason',
        key: const ValueKey('review-reason-counter'),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One task of the day: a fixed icon column, time and title on the first line
/// (title up to two lines, then an ellipsis with a tooltip), outcome pill and
/// planned time on the second, then the reason field and quick-reason chips
/// for tasks that are not Completed.
///
/// The row owns its text controller (made once, disposed with the row) and
/// listens to the draft only for re-hydration and the enabled flag, so typing
/// here rebuilds this row and nothing else.
class TaskOutcomeRowView extends ConsumerStatefulWidget {
  final DateTime date;
  final TaskOutcomeRow row;
  final bool showDivider;
  final List<String> presets;
  final ValueChanged<String> onSaveAsPreset;

  const TaskOutcomeRowView({
    super.key,
    required this.date,
    required this.row,
    required this.showDivider,
    required this.presets,
    required this.onSaveAsPreset,
  });

  @override
  ConsumerState<TaskOutcomeRowView> createState() => _TaskOutcomeRowViewState();
}

class _TaskOutcomeRowViewState extends ConsumerState<TaskOutcomeRowView> {
  late final TextEditingController _reason;
  final _focus = FocusNode();
  ProviderSubscription<int>? _hydration;

  /// Whether the "Noted" check fades in. True only when it appears because
  /// the user just left the field or tapped a preset chip; text that was
  /// already there (restored draft, saved review) shows it at once.
  bool _animateNoted = false;

  String _storedReason() =>
      ref.read(reviewDraftProvider(widget.date)).reasons[widget.row.taskId] ??
      '';

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController(text: _storedReason());
    _focus.addListener(_onFocusChanged);
    _listenForHydration();
  }

  void _listenForHydration() {
    _hydration?.close();
    _hydration = ref.listenManual(
      reviewDraftProvider(widget.date).select((d) => d.hydrationVersion),
      (_, _) => _reload(),
    );
  }

  /// Stored values replaced the draft: show them (typing never gets here).
  void _reload() {
    final stored = _storedReason();
    if (_reason.text == stored) return;
    _reason.text = stored;
    _animateNoted = false;
    if (mounted) setState(() {});
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
    if (oldWidget.date != widget.date) {
      _listenForHydration();
      _reload();
    }
  }

  @override
  void dispose() {
    _hydration?.close();
    _focus.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onReasonChanged(String text) => ref
      .read(reviewDraftProvider(widget.date).notifier)
      .setReason(widget.row.taskId, text);

  void _applyPreset(String preset) {
    _reason.value = TextEditingValue(
      text: preset,
      selection: TextSelection.collapsed(offset: preset.length),
    );
    _onReasonChanged(preset);
    if (defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.selectionClick();
    }
    _animateNoted = true;
    _focus.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final caption = weeklyCaptionStyle(context);
    final row = widget.row;
    final enabled = ref.watch(
      reviewDraftProvider(widget.date).select((d) => d.hydrated),
    );
    final time = DateFormat('HH:mm')
        .format(PlannerTimeZone.toPlannerLocal(row.startTime!));
    final meta =
        '${Duration(minutes: row.plannedMinutes).shortLabel} planned'
        '${row.trackedMinutes > 0 ? ' · ${Duration(minutes: row.trackedMinutes).shortLabel} tracked' : ''}';
    final chips = ReviewReasonPresets.chips(widget.presets);
    const saveLabel = '+ Save as preset';
    final chipMinWidth =
        measureWidestText(context, [
          ...chips,
          saveLabel,
        ], textTheme.labelLarge) +
        2 * AppSpacing.lg +
        AppSpacing.sm;

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
          SizedBox(
            width: 24,
            child: Icon(
              taskOutcomeIcon(row.outcome),
              size: 24,
              color: taskOutcomeColor(context, row.outcome),
              semanticLabel: row.outcome.label,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: row.planChange == null
                      ? CrossAxisAlignment.baseline
                      : CrossAxisAlignment.start,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(time, style: caption),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: row.planChange != null
                          ? PlanChangeBlock(
                              key: ValueKey('review-plan-change-${row.taskId}'),
                              change: row.planChange!,
                            )
                          : Tooltip(
                              message: row.title,
                              excludeFromSemantics: true,
                              child: Text(
                                row.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TaskOutcomePill(outcome: row.outcome, roomy: true),
                    Text(meta, style: caption),
                  ],
                ),
                if (row.outcome != TaskOutcome.completed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    label: 'Reason for ${row.title}',
                    child: TextField(
                      key: ValueKey('review-reason-${row.taskId}'),
                      controller: _reason,
                      focusNode: _focus,
                      enabled: enabled,
                      maxLines: 1,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(maxReviewReasonLength),
                      ],
                      decoration:
                          WeeklyStyle.fieldDecoration(
                            context,
                            isDense: true,
                            hintText: 'Why was this not done? (optional)',
                          ).copyWith(
                            // "Noted" whenever the field is not being edited
                            // and holds text. Nothing is persisted until
                            // "Save review".
                            suffixIcon: _NotedBadge(
                              visible:
                                  !_focus.hasFocus &&
                                  _reason.text.trim().isNotEmpty,
                              animate: _animateNoted,
                            ),
                            suffixIconConstraints: const BoxConstraints(),
                          ),
                      onChanged: _onReasonChanged,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _reason,
                    builder: (context, value, _) {
                      final canSave = ReviewReasonPresets.canSaveAsPreset(
                        widget.presets,
                        value.text,
                      );
                      if (chips.isEmpty && !canSave) {
                        return const SizedBox.shrink();
                      }
                      return ReviewAnimatedSize(
                        child: ReviewCellGrid(
                          minCellWidth: chipMinWidth,
                          spacing: AppSpacing.sm,
                          children: [
                            for (final p in chips)
                              ReviewPresetChip(
                                label: p,
                                onPressed: enabled
                                    ? () => _applyPreset(p)
                                    : null,
                              ),
                            if (canSave)
                              ReviewGhostChip(
                                key: ValueKey(
                                  'review-save-as-preset-${row.taskId}',
                                ),
                                label: saveLabel,
                                onPressed: () =>
                                    widget.onSaveAsPreset(value.text.trim()),
                              ),
                          ],
                        ),
                      );
                    },
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

  /// Text between `PLAN CHANGED` and the reason: two spaces in Daily,
  /// ` · ` in Weekly (WD29).
  final String reasonSeparator;

  const PlanChangeBlock({
    super.key,
    required this.change,
    this.reasonSeparator = '  ',
  });

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
                    text: '$reasonSeparator${change.reason}',
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
