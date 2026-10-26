import '../providers/double_click_tip_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/breakpoints.dart';
import '../../../../core/layout/size_class_scope.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../review/presentation/widgets/weekly_review_style.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../../../timer/presentation/widgets/timer_overlay.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../widgets/attention/day_attention_section.dart';
import '../widgets/day_header_bar.dart';
import '../widgets/day_layout.dart';
import '../widgets/day_side_panel.dart';
import '../widgets/day_style.dart';
import '../widgets/timeline_widget.dart';

class DayViewScreen extends ConsumerStatefulWidget {
  const DayViewScreen({super.key});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  bool _mobileEditorOpen = false;

  /// Keys the timeline column so a size-class change moves it between the
  /// compact column and the wide row instead of remounting it (scroll
  /// position, selection and drag state survive).
  late final GlobalKey _timelineKey;

  @override
  void initState() {
    super.initState();
    _timelineKey = GlobalKey(debugLabel: 'day-timeline-area');
  }

  Future<void> _openMobileEditor() async {
    if (_mobileEditorOpen || !mounted) return;
    setState(() => _mobileEditorOpen = true);
    ref.read(taskEditorOpenProvider.notifier).state = true;
    await TaskEditorPanel.showAsBottomSheet(context);
    if (mounted) setState(() => _mobileEditorOpen = false);
  }

  void _requestEdit(Task task, {required bool sidePanel}) {
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
    ref.read(taskEditorOpenProvider.notifier).state = true;
    if (!sidePanel) unawaited(_openMobileEditor());
  }

  void _swipeDay(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;
    final notifier = ref.read(selectedDateProvider.notifier);
    notifier.state = addDays(notifier.state, velocity < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    void closeEditor() {
      ref.read(taskEditorOpenProvider.notifier).state = false;
      ref.read(selectedTaskIdProvider.notifier).state = null;
    }

    final sizeClass = DaySizeClass.of(context);
    final sidePanel = Breakpoints.hasSidePanel(sizeClass);
    final selectedTaskId = ref.watch(selectedTaskIdProvider);
    final editorRequested = ref.watch(taskEditorOpenProvider);
    // Search and Week set an explicit editor request before navigating to
    // Day. Selection alone never opens an editor.
    if (!sidePanel &&
        selectedTaskId != null &&
        editorRequested &&
        !_mobileEditorOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openMobileEditor());
      });
    }
    final editorOpen = sidePanel && selectedTaskId != null && editorRequested;

    final timelineArea = KeyedSubtree(
      key: _timelineKey,
      child: Column(
        children: [
          const _DayMaterializationStatus(),
          const _DayCreateTip(),
          Expanded(
            child: TimelineWidget(
              onEditTask: (task) => _requestEdit(task, sidePanel: sidePanel),
              // The phone's New task button floats over the right-hand lane:
              // leave room to scroll the last blocks (and their resize
              // corner) clear of it.
              bottomInset: sizeClass.isCompact ? AppSpacing.huge : 0,
            ),
          ),
        ],
      ),
    );

    // The timeline column with the timer overlay at its bottom-right.
    Widget cappedTimeline() => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DayLayout.timelineMaxWidth),
        child: Stack(
          fit: StackFit.expand,
          children: [
            timelineArea,
            const Positioned(
              bottom: AppSpacing.lg,
              right: AppSpacing.lg,
              child: TimerOverlay(),
            ),
          ],
        ),
      ),
    );

    if (sizeClass.isCompact) {
      return Scaffold(
        floatingActionButton: _mobileEditorOpen
            ? null
            : WeeklyPressScale(
                child: FloatingActionButton.extended(
                  key: const ValueKey('day-new-task-fab'),
                  onPressed: () => requestNewTask(ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                ),
              ),
        body: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              const DayHeaderBar(),
              const DayAttentionBanner(),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _swipeDay,
                      child: timelineArea,
                    ),
                    // Left-aligned and above the FAB row so the two never
                    // overlap, whatever width the timer needs.
                    const Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md + 56 + AppSpacing.sm,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TimerOverlay(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sizeClass == WindowSizeClass.medium) {
      return Column(
        children: [
          const DayHeaderBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  DayAttentionStrip(
                    maxHeight:
                        constraints.maxHeight *
                        DayLayout.stripMaxHeightFraction,
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _swipeDay,
                      child: cappedTimeline(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final large = sizeClass == WindowSizeClass.large;
    return Column(
      children: [
        const DayHeaderBar(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: large ? DayLayout.contentMaxWidth : double.infinity,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cappedTimeline()),
                  if (editorOpen) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: TaskEditorPanel(
                        presentation: TaskEditorPresentation.desktopPanel,
                        onClose: closeEditor,
                      ),
                    ),
                  ] else
                    const DaySidePanel(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps recurrence materialization tied to the currently viewed date without
/// making the surrounding Day layout subscribe to a legacy selection provider.
class _DayMaterializationStatus extends ConsumerWidget {
  const _DayMaterializationStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final materialization = ref.watch(dayMaterializationProvider(date));
    if (!materialization.hasError) return const SizedBox.shrink();
    return ErrorPanel(
      message: friendlyErrorMessage(materialization.error!),
      onRetry: () => ref.invalidate(dayMaterializationProvider(date)),
    );
  }
}

/// One-time tip that tapping an empty slot adds a task.
class _DayCreateTip extends ConsumerWidget {
  const _DayCreateTip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dayCreateTipDismissedProvider).value;
    // Hidden while loading so it never flashes for a user who already
    // dismissed it.
    if (dismissed != false) return const SizedBox.shrink();
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(DayStyle.small(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: Row(
            key: const ValueKey('day-create-tip'),
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Tip: tap an empty slot to add a task.',
                  style: DayStyle.secondary(context),
                ),
              ),
              TextButton(
                key: const ValueKey('day-create-tip-dismiss'),
                onPressed: () =>
                    ref.read(dayCreateTipDismissedProvider.notifier).dismiss(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
