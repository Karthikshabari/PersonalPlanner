import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../providers/selected_date_provider.dart';

class DayHeader extends ConsumerWidget {
  const DayHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final notifier = ref.read(selectedDateProvider.notifier);
    final label = DateFormat('MMM d, yyyy').format(selectedDate);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => notifier.state =
                selectedDate.subtract(const Duration(days: 1)),
          ),
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                notifier.state = selectedDate.add(const Duration(days: 1)),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: () {
              final now = DateTime.now();
              notifier.state = DateTime(now.year, now.month, now.day);
            },
            child: const Text('Today'),
          ),
          SegmentedButton<String>(
            key: const ValueKey('day-week-switcher'),
            segments: const [
              ButtonSegment(value: 'day', label: Text('Day')),
              ButtonSegment(value: 'week', label: Text('Week')),
            ],
            selected: const {'day'},
            onSelectionChanged: (selection) {
              if (selection.contains('week')) context.go('/week');
            },
          ),
        ],
      ),
    );
  }
}
