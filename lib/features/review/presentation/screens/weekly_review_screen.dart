import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/weekly_review.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/utils/duration_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/review_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../widgets/rating_picker.dart';
import '../widgets/string_list_editor.dart';

class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final statsAsync = ref.watch(weeklyStatsProvider(weekStart));
    final tokens = AppThemeTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Review'),
        actions: [
          IconButton(
            key: const ValueKey('open-daily-review'),
            tooltip: 'Daily review',
            icon: const Icon(Icons.calendar_view_day_outlined),
            onPressed: () {
              if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
                context.go('/review');
              } else {
                context.push('/review');
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
              _buildWeekNav(context, ref, weekStart),
              _AggregateStatsCard(statsAsync: statsAsync),
              const SizedBox(height: AppSpacing.md),
              _WeeklyReviewForm(
                key: ValueKey('weekly-form-$weekStart'),
                weekStart: weekStart,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekNav(
    BuildContext context,
    WidgetRef ref,
    DateTime weekStart,
  ) {
    final notifier = ref.read(selectedWeekStartProvider.notifier);
    final weekEnd = addDays(weekStart, 6);
    final fmt = DateFormat('MMM d');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        IconButton(
          key: const ValueKey('week-prev'),
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => notifier.state = addDays(weekStart, -7),
        ),
        Text(
          '${fmt.format(weekStart)} – ${DateFormat('MMM d, yyyy').format(weekEnd)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          key: const ValueKey('week-next'),
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => notifier.state = addDays(weekStart, 7),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => notifier.state = startOfWeek(DateTime.now()),
          child: const Text('This Week'),
        ),
      ],
    );
  }
}

/// Sum/average of the seven daily aggregates (planner.md Chunk 5 #6).
class _AggregateStatsCard extends StatelessWidget {
  final AsyncValue<DailyStats> statsAsync;

  const _AggregateStatsCard({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          statsAsync.when(
            data: (stats) {
              final rate = stats.completionRatePct;
              return Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.sm,
                children: [
                  _stat(
                    context,
                    'Completion rate',
                    rate == null ? '—' : '${rate.round()}%',
                  ),
                  _stat(
                    context,
                    'Completed',
                    '${stats.completedTasks}/${stats.totalTasks} tasks',
                  ),
                  _stat(context, 'Planned', '${stats.plannedTasks}'),
                  _stat(context, 'In progress', '${stats.inProgressTasks}'),
                  _stat(
                    context,
                    'Planned time',
                    Duration(minutes: stats.plannedDurationMin).shortLabel,
                  ),
                  _stat(
                    context,
                    'Actual',
                    Duration(minutes: stats.actualDurationMin).shortLabel,
                  ),
                  _stat(
                    context,
                    'Focus',
                    Duration(minutes: stats.focusDurationMin).shortLabel,
                  ),
                  _stat(context, 'Missed', '${stats.missedTasks}'),
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

  Widget _stat(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _WeeklyReviewForm extends ConsumerStatefulWidget {
  final DateTime weekStart;

  const _WeeklyReviewForm({super.key, required this.weekStart});

  @override
  ConsumerState<_WeeklyReviewForm> createState() => _WeeklyReviewFormState();
}

class _WeeklyReviewFormState extends ConsumerState<_WeeklyReviewForm> {
  final _reflectionController = TextEditingController();
  int? _overall;
  List<String> _goalsMet = [];
  List<String> _goalsMissed = [];
  List<String> _nextFocus = [];
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
          .getWeeklyReviewForWeek(widget.weekStart);
      if (!mounted || existing == null) return;
      setState(() {
        _reflectionController.text = existing.reflection ?? '';
        _overall = existing.overallRating;
        _goalsMet = [...existing.goalsMet];
        _goalsMissed = [...existing.goalsMissed];
        _nextFocus = [...existing.nextWeekFocus];
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(reviewRepositoryProvider);
      await repo.saveWeeklyReview(
        WeeklyReview(
          id: '',
          weekStartDate: widget.weekStart,
          reflection: _reflectionController.text.trim().isEmpty
              ? null
              : _reflectionController.text.trim(),
          overallRating: _overall,
          goalsMet: _goalsMet,
          goalsMissed: _goalsMissed,
          nextWeekFocus: _nextFocus,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Weekly review saved');
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
            key: const ValueKey('weekly-reflection'),
            controller: _reflectionController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'How did the week go?',
              labelText: 'Reflection',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          RatingPicker(
            label: 'Overall rating',
            value: _overall,
            onChanged: (v) => setState(() => _overall = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          StringListEditor(
            key: const ValueKey('weekly-goals-met'),
            label: 'Goals met',
            items: _goalsMet,
            onChanged: (items) => setState(() => _goalsMet = items),
          ),
          StringListEditor(
            key: const ValueKey('weekly-goals-missed'),
            label: 'Goals missed',
            items: _goalsMissed,
            onChanged: (items) => setState(() => _goalsMissed = items),
          ),
          StringListEditor(
            key: const ValueKey('weekly-next-focus'),
            label: 'Next week focus',
            items: _nextFocus,
            onChanged: (items) => setState(() => _nextFocus = items),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const ValueKey('weekly-save'),
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
