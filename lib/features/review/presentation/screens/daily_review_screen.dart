import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/category.dart';
import '../../../../core/models/daily_review.dart';
import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../providers/review_providers.dart';
import '../widgets/day_summary_timeline.dart';
import '../widgets/rating_picker.dart';
import '../widgets/string_list_editor.dart';

class DailyReviewScreen extends ConsumerWidget {
  const DailyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedReviewDateProvider);
    final tasksAsync = ref.watch(dayTasksForDateProvider(date));
    final categoriesAsync = ref.watch(categoriesProvider);
    final statsAsync = ref.watch(dailyStatsProvider(date));

    final tasks =
        tasksAsync.maybeWhen(data: (t) => t, orElse: () => const <Task>[]);
    final categories = categoriesAsync.maybeWhen(
        data: (c) => c, orElse: () => const <Category>[]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Review'),
        actions: [
          IconButton(
            key: const ValueKey('open-weekly-review'),
            tooltip: 'Weekly review',
            icon: const Icon(Icons.calendar_view_week_outlined),
            onPressed: () => context.go('/review/weekly'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _buildDateNav(context, ref, date),
          _StatsCard(statsAsync: statsAsync),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's blocks",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  DaySummaryTimeline(
                      tasks: tasks, categories: categories, date: date),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _DailyReviewForm(key: ValueKey('review-form-$date'), date: date),
        ],
      ),
    );
  }

  Widget _buildDateNav(BuildContext context, WidgetRef ref, DateTime date) {
    final notifier = ref.read(selectedReviewDateProvider.notifier);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        IconButton(
          key: const ValueKey('review-prev-day'),
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              notifier.state = date.subtract(const Duration(days: 1)),
        ),
        Text(
          DateFormat('EEE, MMM d, yyyy').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          key: const ValueKey('review-next-day'),
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => notifier.state = date.add(const Duration(days: 1)),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () {
            final now = DateTime.now();
            notifier.state = DateTime(now.year, now.month, now.day);
          },
          child: const Text('Today'),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final AsyncValue<DailyStats> statsAsync;

  const _StatsCard({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auto-computed stats',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            statsAsync.maybeWhen(
              data: (stats) {
                final rate = stats.completionRatePct;
                final breakdown = <Widget>[
                  for (final status in TaskStatus.values)
                    if (_countFor(stats, status) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.md),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusBadge(status: status),
                            const SizedBox(width: AppSpacing.xs),
                            Text('${_countFor(stats, status)}'),
                          ],
                        ),
                      ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _stat(context, 'Completion rate',
                            rate == null ? '—' : '${rate.round()}%'),
                        const SizedBox(width: AppSpacing.xl),
                        _stat(context, 'Planned',
                            Duration(minutes: stats.plannedDurationMin).shortLabel),
                        const SizedBox(width: AppSpacing.xl),
                        _stat(context, 'Actual',
                            Duration(minutes: stats.actualDurationMin).shortLabel),
                      ],
                    ),
                    if (breakdown.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(children: breakdown),
                    ],
                    if (stats.planningAccuracyPct != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Planning accuracy: ${stats.planningAccuracyPct!.round()}% '
                        '(actual vs estimated)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                );
              },
              orElse: () => const Text('Computing…'),
            ),
          ],
        ),
      ),
    );
  }

  int _countFor(DailyStats stats, TaskStatus status) => switch (status) {
        TaskStatus.completed => stats.completedTasks,
        TaskStatus.planned => stats.plannedTasks,
        TaskStatus.inProgress => stats.inProgressTasks,
        TaskStatus.skipped => stats.skippedTasks,
        TaskStatus.cancelled => stats.cancelledTasks,
        TaskStatus.rescheduled => stats.rescheduledTasks,
      };

  Widget _stat(BuildContext context, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _DailyReviewForm extends ConsumerStatefulWidget {
  final DateTime date;

  const _DailyReviewForm({super.key, required this.date});

  @override
  ConsumerState<_DailyReviewForm> createState() => _DailyReviewFormState();
}

class _DailyReviewFormState extends ConsumerState<_DailyReviewForm> {
  final _reflectionController = TextEditingController();
  int? _energy;
  int? _productivity;
  int? _accuracy;
  List<String> _wins = [];
  List<String> _improvements = [];

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final existing =
        await ref.read(reviewRepositoryProvider).getReviewForDate(widget.date);
    if (!mounted || existing == null) return;
    setState(() {
      _apply(existing);
    });
  }

  void _apply(DailyReview review) {
    _reflectionController.text = review.reflection ?? '';
    _energy = review.energyLevel;
    _productivity = review.productivityRating;
    _accuracy = review.planningAccuracyRating;
    _wins = [...review.wins];
    _improvements = [...review.improvements];
  }

  Future<void> _save() async {
    final repo = ref.read(reviewRepositoryProvider);
    await repo.saveDailyReview(DailyReview(
      id: '',
      date: widget.date,
      reflection:
          _reflectionController.text.trim().isEmpty
              ? null
              : _reflectionController.text.trim(),
      energyLevel: _energy,
      productivityRating: _productivity,
      planningAccuracyRating: _accuracy,
      wins: _wins,
      improvements: _improvements,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    // Refresh the cached aggregates so analytics and reviews stay in sync
    // (planner.md Chunk 5 #9 trigger).
    await ref.read(dailyStatsServiceProvider).computeAndCache(widget.date);
    if (!mounted) return;
    showAppToast(context, 'Daily review saved');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('review-reflection'),
              controller: _reflectionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'How did the day go?',
                labelText: 'Reflection',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            RatingPicker(
              label: 'Energy level',
              value: _energy,
              onChanged: (v) => setState(() => _energy = v),
            ),
            RatingPicker(
              label: 'Productivity',
              value: _productivity,
              onChanged: (v) => setState(() => _productivity = v),
            ),
            RatingPicker(
              label: 'Planning accuracy',
              value: _accuracy,
              onChanged: (v) => setState(() => _accuracy = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            StringListEditor(
              key: const ValueKey('review-wins'),
              label: 'Wins',
              items: _wins,
              hint: 'What went well?',
              onChanged: (items) => setState(() => _wins = items),
            ),
            StringListEditor(
              key: const ValueKey('review-improvements'),
              label: 'Improvements',
              items: _improvements,
              hint: 'What to do better?',
              onChanged: (items) => setState(() => _improvements = items),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('review-save'),
              onPressed: _save,
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
  }
}
