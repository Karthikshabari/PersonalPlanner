import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../inbox/presentation/widgets/day_needs_attention.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../../../timer/presentation/widgets/timer_overlay.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../widgets/day_header.dart';
import '../widgets/timeline_widget.dart';

class DayViewScreen extends ConsumerStatefulWidget {
  const DayViewScreen({super.key});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  bool _mobileEditorOpen = false;

  Future<void> _openMobileEditor() async {
    if (_mobileEditorOpen || !mounted) return;
    setState(() => _mobileEditorOpen = true);
    ref.read(taskEditorOpenProvider.notifier).state = true;
    await TaskEditorPanel.showAsBottomSheet(context);
    if (mounted) setState(() => _mobileEditorOpen = false);
  }

  void _requestEdit(Task task, {required bool desktop}) {
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
    ref.read(taskEditorOpenProvider.notifier).state = true;
    if (!desktop) unawaited(_openMobileEditor());
  }

  @override
  Widget build(BuildContext context) {
    void closeEditor() {
      ref.read(taskEditorOpenProvider.notifier).state = false;
      ref.read(selectedTaskIdProvider.notifier).state = null;
    }

    final selectedDate = ref.read(selectedDateProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = isDesktopWidth(constraints.maxWidth);
        final selectedTaskId = ref.watch(selectedTaskIdProvider);
        final editorRequested = ref.watch(taskEditorOpenProvider);
        // Search and Week set an explicit editor request before navigating to
        // Day. Selection alone never opens an editor.
        if (!isDesktop &&
            selectedTaskId != null &&
            editorRequested &&
            !_mobileEditorOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openMobileEditor());
          });
        }
        final showDesktopEditor =
            isDesktop && selectedTaskId != null && editorRequested;

        final timeline = Column(
          children: [
            const _DayMaterializationStatus(),
            Expanded(
              child: TimelineWidget(
                onEditTask: (task) => _requestEdit(task, desktop: isDesktop),
              ),
            ),
          ],
        );

        if (isDesktop) {
          return Stack(
            children: [
              Column(
                children: [
                  const DayHeader(),
                  const DayNeedsAttention(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: timeline),
                        if (showDesktopEditor) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 340,
                            child: TaskEditorPanel(
                              presentation: TaskEditorPresentation.desktopPanel,
                              onClose: closeEditor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: AppSpacing.lg,
                right: showDesktopEditor ? 340 + AppSpacing.lg : AppSpacing.lg,
                child: const TimerOverlay(),
              ),
            ],
          );
        }

        return SafeArea(
          top: true,
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 250) return;
              final notifier = ref.read(selectedDateProvider.notifier);
              notifier.state = velocity < 0
                  ? addDays(selectedDate, 1)
                  : addDays(selectedDate, -1);
            },
            child: Column(
              children: [
                const DayHeader(),
                const DayNeedsAttention(),
                Expanded(child: timeline),
              ],
            ),
          ),
        );
      },
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
