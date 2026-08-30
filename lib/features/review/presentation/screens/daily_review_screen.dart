import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/daily_review.dart';
import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/enums/task_status.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
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
    final tokens = AppThemeTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Review'),
        actions: [
          IconButton(
            key: const ValueKey('open-weekly-review'),
            tooltip: 'Weekly review',
            icon: const Icon(Icons.calendar_view_week_outlined),
            onPressed: () {
              if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
                context.go('/review/weekly');
              } else {
                context.push('/review/weekly');
              }
            },
          ),
          const SyncStatusAction(),
        ],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.all(
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.lg,
            ),
            children: [
              _buildDateNav(context, ref, date),
              _StatsCard(statsAsync: statsAsync),
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's blocks",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (tasksAsync.hasError)
                      ErrorPanel(
                        message: friendlyErrorMessage(tasksAsync.error!),
                        onRetry: () =>
                            ref.invalidate(dayTasksForDateProvider(date)),
                        compact: true,
                      ),
                    if (!tasksAsync.hasError && categoriesAsync.hasError)
                      ErrorPanel(
                        message: friendlyErrorMessage(categoriesAsync.error!),
                        onRetry: () => ref.invalidate(categoriesProvider),
                        compact: true,
                      ),
                    if (!tasksAsync.hasError &&
                        !categoriesAsync.hasError &&
                        (!tasksAsync.hasValue || !categoriesAsync.hasValue))
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.sm),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!tasksAsync.hasError &&
                        !categoriesAsync.hasError &&
                        tasksAsync.hasValue &&
                        categoriesAsync.hasValue)
                      DaySummaryTimeline(
                        tasks: tasksAsync.requireValue,
                        categories: categoriesAsync.requireValue,
                        date: date,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _DailyReviewForm(key: ValueKey('review-form-$date'), date: date),
            ],
          ),
        ),
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
          onPressed: () => notifier.state = addDays(date, -1),
        ),
        Text(
          DateFormat('EEE, MMM d, yyyy').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          key: const ValueKey('review-next-day'),
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => notifier.state = addDays(date, 1),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () {
            final now = DateTime.now();
            notifier.state = startOfDay(now);
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
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auto-computed stats',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          statsAsync.when(
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
                      _stat(
                        context,
                        'Completion rate',
                        rate == null ? '—' : '${rate.round()}%',
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      _stat(
                        context,
                        'Planned',
                        Duration(minutes: stats.plannedDurationMin).shortLabel,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      _stat(
                        context,
                        'Actual',
                        Duration(minutes: stats.actualDurationMin).shortLabel,
                      ),
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
            loading: () => const CircularProgressIndicator(),
            error: (error, _) =>
                ErrorPanel(message: friendlyErrorMessage(error), compact: true),
          ),
        ],
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
  bool _saving = false;
  String? _error;

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
    try {
      final existing = await ref
          .read(reviewRepositoryProvider)
          .getReviewForDate(widget.date);
      if (!mounted || existing == null) return;
      setState(() => _apply(existing));
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
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
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(reviewRepositoryProvider);
      await repo.saveDailyReview(
        DailyReview(
          id: '',
          date: widget.date,
          reflection: _reflectionController.text.trim().isEmpty
              ? null
              : _reflectionController.text.trim(),
          energyLevel: _energy,
          productivityRating: _productivity,
          planningAccuracyRating: _accuracy,
          wins: _wins,
          improvements: _improvements,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      // Refresh the cached aggregates so analytics and reviews stay in sync
      // (planner.md Chunk 5 #9 trigger).
      await ref.read(dailyStatsServiceProvider).computeAndCache(widget.date);
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Daily review saved');
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_error != null)
            ErrorPanel(message: _error!, onRetry: _hydrate, compact: true),
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
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save review'),
          ),
        ],
      ),
    );
  }
}
