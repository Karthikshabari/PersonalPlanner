import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../../review/providers/review_providers.dart';
import '../../../day_context/presentation/day_context_editor.dart';
import '../providers/selected_date_provider.dart';

class DayHeader extends ConsumerWidget {
  const DayHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final notifier = ref.read(selectedDateProvider.notifier);
    final label = DateFormat('MMM d, yyyy').format(selectedDate);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The shell's rail consumes part of a desktop window. Use the
        // available header width rather than the outer-window breakpoint so
        // the full desktop row does not overflow at intermediate desktop
        // sizes (for example a 1280px window with the editor rail).
        final compact = constraints.maxWidth < 1200;
        final tokens = AppThemeTokens.of(context);
        return Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(
              bottom: BorderSide(color: tokens.outline.withValues(alpha: 0.7)),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.sm : AppSpacing.lg,
              vertical: compact ? AppSpacing.xs : AppSpacing.sm,
            ),
            child: compact
                ? _buildCompactHeader(
                    context,
                    ref,
                    notifier,
                    selectedDate,
                    label,
                  )
                : _buildDesktopHeader(
                    context,
                    ref,
                    notifier,
                    selectedDate,
                    label,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopHeader(
    BuildContext context,
    WidgetRef ref,
    StateController<DateTime> notifier,
    DateTime selectedDate,
    String label,
  ) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => notifier.state = addDays(selectedDate, -1),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DAY PLAN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppThemeTokens.of(context).textMuted,
                letterSpacing: 1.4,
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            DayContextAction(date: selectedDate, compact: true),
          ],
        ),
        IconButton(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => notifier.state = addDays(selectedDate, 1),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => _setToday(notifier),
          child: const Text('Today'),
        ),
        const SizedBox(width: AppSpacing.xs),
        _buildDayWeekSwitcher(context, ref, selectedDate),
        const Spacer(),
        TextButton.icon(
          key: const ValueKey('day-settings-action'),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Settings'),
          onPressed: () => context.go('/settings'),
        ),
        const SyncStatusAction(),
      ],
    );
  }

  /// A fixed two-row composition keeps every action reachable at 360dp and
  /// 390dp without Wrap creating an unpredictable multi-row header.
  Widget _buildCompactHeader(
    BuildContext context,
    WidgetRef ref,
    StateController<DateTime> notifier,
    DateTime selectedDate,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => notifier.state = addDays(selectedDate, -1),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => notifier.state = addDays(selectedDate, 1),
            ),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: DayContextAction(date: selectedDate, compact: true),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setToday(notifier),
                child: const Text('Today'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _buildDayWeekSwitcher(context, ref, selectedDate),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              key: const ValueKey('day-settings-action'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
            const SyncStatusAction(),
          ],
        ),
      ],
    );
  }

  Widget _buildDayWeekSwitcher(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
  ) => SegmentedButton<String>(
    key: const ValueKey('day-week-switcher'),
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: 'day', label: Text('Day')),
      ButtonSegment(value: 'week', label: Text('Week')),
    ],
    selected: const {'day'},
    onSelectionChanged: (selection) {
      if (selection.contains('week')) {
        ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(
          selectedDate,
        );
        context.go('/week');
      }
    },
  );

  void _setToday(StateController<DateTime> notifier) {
    final now = DateTime.now();
    notifier.state = startOfDay(now);
  }
}
