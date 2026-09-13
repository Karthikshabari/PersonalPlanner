import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../inbox/presentation/widgets/inbox_sidebar.dart';
import '../../../task_editor/presentation/screens/task_editor_panel.dart';
import '../providers/selected_date_provider.dart';
import '../providers/selected_task_provider.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../timer/presentation/widgets/timer_overlay.dart';
import '../../../../core/widgets/error_panel.dart';
import '../widgets/day_header.dart';
import '../widgets/timeline_widget.dart';

class DayViewScreen extends ConsumerWidget {
  const DayViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Materialize recurring rules for the viewed date (Chunk 4 #3). Watching
    // the provider keeps the work alive and re-runs when the date changes.
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
        if (isDesktop) {
          return Stack(
            children: [
              Column(
                children: [
                  DayHeader(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              materializationError ?? const SizedBox.shrink(),
                              const Expanded(child: TimelineWidget()),
                            ],
                          ),
                        ),
                        VerticalDivider(width: 1),
                        SizedBox(
                          width: 340,
                          child: TaskEditorPanel(
                            presentation: TaskEditorPresentation.desktopPanel,
                            onClose: () =>
                                ref
                                        .read(selectedTaskIdProvider.notifier)
                                        .state =
                                    null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InboxSidebar(),
                ],
              ),
              // Floating running-timer widget (Chunk 6 #8).
              Positioned(
                bottom: AppSpacing.lg,
                left: AppSpacing.lg,
                right: 340 + AppSpacing.lg,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: TimerOverlay(),
                ),
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
                Expanded(
                  child: Column(
                    children: [
                      materializationError ?? const SizedBox.shrink(),
                      Expanded(
                        child: TimelineWidget(
                          onTaskTap: (_) => TaskEditorPanel.showAsBottomSheet(
                            context,
                            onClose: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
