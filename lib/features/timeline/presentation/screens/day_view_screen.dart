import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/adaptive_layout.dart';
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

class DayViewScreen extends ConsumerWidget {
  const DayViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(selectedTaskIdProvider, (previous, next) {
      if (next != null && previous != next) {
        ref.read(taskEditorOpenProvider.notifier).state = true;
      }
    });
    void closeEditor() {
      ref.read(taskEditorOpenProvider.notifier).state = false;
      ref.read(selectedTaskIdProvider.notifier).state = null;
    }

    Future<void> openMobileEditor() async {
      await TaskEditorPanel.showAsBottomSheet(
        context,
        onClose: () => Navigator.of(context).pop(),
      );
      ref.read(taskEditorOpenProvider.notifier).state = false;
    }

    final selectedDate = ref.watch(selectedDateProvider);
    final materialization = ref.watch(dayMaterializationProvider(selectedDate));
    final materializationError = materialization.hasError
        ? ErrorPanel(
            message: friendlyErrorMessage(materialization.error!),
            onRetry: () =>
                ref.invalidate(dayMaterializationProvider(selectedDate)),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = isDesktopWidth(constraints.maxWidth);
        // Selection is written immediately before opening the editor from all
        // entry points; reading it avoids keeping a legacy StateProvider
        // subscription alive across route replacement.
        final selectedTaskId = ref.read(selectedTaskIdProvider);
        // This provider is the rebuild signal for selection changes; the
        // selected task itself remains a non-reactive read to avoid a closed
        // legacy StateProvider subscription during route replacement.
        final editorOpen = ref.watch(taskEditorOpenProvider);
        if (selectedTaskId != null && !editorOpen) {
          // A few existing entry points select a task immediately before
          // routing to Day. Open the on-demand panel after this frame without
          // subscribing to the legacy selection provider.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            if (ref.read(selectedTaskIdProvider) == selectedTaskId &&
                !ref.read(taskEditorOpenProvider)) {
              ref.read(taskEditorOpenProvider.notifier).state = true;
            }
          });
        }
        final showDesktopEditor = isDesktop && selectedTaskId != null;

        final timeline = Column(
          children: [
            materializationError ?? const SizedBox.shrink(),
            Expanded(
              child: TimelineWidget(
                onTaskTap: isDesktop
                    ? (_) =>
                          ref.read(taskEditorOpenProvider.notifier).state = true
                    : (_) => openMobileEditor(),
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
