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

class DayViewScreen extends ConsumerStatefulWidget {
  const DayViewScreen({super.key});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  bool _editorVisible = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedTaskIdProvider, (previous, next) {
      if (next != null && previous != next && mounted) {
        setState(() => _editorVisible = true);
      }
    });
    void closeEditor() {
      setState(() => _editorVisible = false);
      ref.read(taskEditorOpenProvider.notifier).state = false;
      ref.read(selectedTaskIdProvider.notifier).state = null;
    }

    Future<void> openMobileEditor() async {
      await TaskEditorPanel.showAsBottomSheet(
        context,
        onClose: () => Navigator.of(context).pop(),
      );
      ref.read(taskEditorOpenProvider.notifier).state = false;
      if (mounted) setState(() => _editorVisible = false);
    }

    final selectedDate = ref.read(selectedDateProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = isDesktopWidth(constraints.maxWidth);
        // Selection is written immediately before opening the editor from all
        // entry points; reading it avoids keeping a legacy StateProvider
        // subscription alive across route replacement.
        final selectedTaskId = ref.read(selectedTaskIdProvider);
        // A selection supplied by Search/Week is an explicit request to
        // open the editor when this route is entered. Local state keeps
        // the panel responsive without subscribing to the legacy
        // selection provider across route/container replacement.
        if (selectedTaskId != null && !_editorVisible) {
          _editorVisible = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ref.read(selectedTaskIdProvider) != null) {
              ref.read(taskEditorOpenProvider.notifier).state = true;
            }
          });
        }
        final showDesktopEditor =
            isDesktop && selectedTaskId != null && _editorVisible;

        final timeline = Column(
          children: [
            const _DayMaterializationStatus(),
            Expanded(
              child: TimelineWidget(
                onEditTask: isDesktop
                    ? (_) {
                        setState(() => _editorVisible = true);
                        ref.read(taskEditorOpenProvider.notifier).state = true;
                      }
                    : null,
                onTaskTap: isDesktop
                    ? (_) {
                        setState(() => _editorVisible = true);
                        ref.read(taskEditorOpenProvider.notifier).state = true;
                      }
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
