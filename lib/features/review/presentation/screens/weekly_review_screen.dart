import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/weekly_review.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/review_insights.dart';
import '../../providers/review_providers.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_sections.dart';

class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final statsAsync = ref.watch(weeklyStatsProvider(weekStart));
    final insightsAsync = ref.watch(weeklyReviewInsightsProvider(weekStart));
    final tokens = AppThemeTokens.of(context);
    final currentWeek = startOfWeek(DateTime.now());
    final future = weekStart.isAfter(currentWeek);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Review'),
        actions: const [SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.all(
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.lg,
            ),
            children: [
              ReviewModeSwitcher(
                weekly: true,
                onChanged: (mode) {
                  if (mode != 'daily') return;
                  ref.read(selectedReviewDateProvider.notifier).state =
                      weekStart;
                  if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
                    context.go('/review');
                  } else {
                    context.push('/review');
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildWeekNav(context, ref, weekStart),
              const SizedBox(height: AppSpacing.md),
              _buildSummary(statsAsync, insightsAsync, future),
              const SizedBox(height: AppSpacing.md),
              _buildChanges(insightsAsync, future),
              const SizedBox(height: AppSpacing.md),
              _buildCarryover(insightsAsync),
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
          '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d, yyyy').format(weekEnd)}',
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
          key: const ValueKey('week-this-week'),
          onPressed: () => notifier.state = startOfWeek(DateTime.now()),
          child: const Text('This Week'),
        ),
      ],
    );
  }

  Widget _buildSummary(
    AsyncValue<DailyStats> stats,
    AsyncValue<ReviewInsights> insights,
    bool future,
  ) {
    if (stats.hasError) {
      return ErrorPanel(message: friendlyErrorMessage(stats.error!));
    }
    if (insights.hasError) {
      return ErrorPanel(message: friendlyErrorMessage(insights.error!));
    }
    if (!stats.hasValue || !insights.hasValue) {
      return const AppSurface(child: LinearProgressIndicator());
    }
    return ReviewSummarySection(
      stats: stats.requireValue,
      insights: insights.requireValue,
      future: future,
      heading: 'This week',
      emptyLabel: 'No planned items for this week.',
    );
  }

  Widget _buildChanges(AsyncValue<ReviewInsights> insights, bool future) {
    if (!insights.hasValue) return const SizedBox.shrink();
    return ReviewChangesSection(
      insights: insights.requireValue,
      future: future,
      heading: 'What changed this week',
    );
  }

  Widget _buildCarryover(AsyncValue<ReviewInsights> insights) {
    if (!insights.hasValue) return const SizedBox.shrink();
    return ReviewCarryoverSection(
      heading: 'Next week',
      items: insights.requireValue.carryover,
    );
  }
}

class _WeeklyReviewForm extends ConsumerStatefulWidget {
  final DateTime weekStart;

  const _WeeklyReviewForm({super.key, required this.weekStart});

  @override
  ConsumerState<_WeeklyReviewForm> createState() => _WeeklyReviewFormState();
}

class _WeeklyReviewFormState extends ConsumerState<_WeeklyReviewForm> {
  final _noteController = TextEditingController();
  WeeklyReview? _existing;
  bool _saving = false;
  bool _hydrated = false;
  bool _hydrating = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    if (mounted) {
      setState(() {
        _hydrating = true;
        _error = null;
      });
    }
    try {
      final existing = await ref
          .read(reviewRepositoryProvider)
          .getWeeklyReviewForWeek(widget.weekStart);
      if (!mounted) return;
      setState(() {
        _existing = existing;
        _noteController.text = existing?.reflection ?? '';
        _hydrated = true;
        _hydrating = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _hydrating = false;
          _hydrated = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_hydrated) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final old = _existing;
      await ref
          .read(reviewRepositoryProvider)
          .saveWeeklyReview(
            WeeklyReview(
              id: old?.id ?? '',
              weekStartDate: widget.weekStart,
              reflection: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              // Keep legacy weekly fields intact while the simplified UI is used.
              overallRating: old?.overallRating,
              goalsMet: old?.goalsMet ?? const [],
              goalsMissed: old?.goalsMissed ?? const [],
              nextWeekFocus: old?.nextWeekFocus ?? const [],
              createdAt: old?.createdAt ?? DateTime.now(),
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
          Text(
            'Anything worth remembering?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Anything from this week that would help you plan the next one?',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_hydrating) const LinearProgressIndicator(),
          if (_error != null)
            ErrorPanel(message: _error!, onRetry: _hydrate, compact: true),
          AbsorbPointer(
            absorbing: !_hydrated || _saving,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('weekly-note'),
                  controller: _noteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Anything from this week that would help you plan the next one?',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  key: const ValueKey('weekly-save'),
                  onPressed: _save,
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
          ),
        ],
      ),
    );
  }
}
