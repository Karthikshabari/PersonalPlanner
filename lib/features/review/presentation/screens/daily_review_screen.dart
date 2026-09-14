import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/daily_review.dart';
import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/day_context.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../day_context/providers/day_context_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/review_insights.dart';
import '../../providers/review_providers.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_sections.dart';

class DailyReviewScreen extends ConsumerWidget {
  const DailyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedReviewDateProvider);
    final statsAsync = ref.watch(dailyStatsProvider(date));
    final insightsAsync = ref.watch(dailyReviewInsightsProvider(date));
    final dayContext = ref.watch(dayContextForDateProvider(date)).value;
    final tokens = AppThemeTokens.of(context);
    final future = startOfDay(date).isAfter(startOfDay(DateTime.now()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Review'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
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
                weekly: false,
                onChanged: (mode) {
                  if (mode != 'weekly') return;
                  ref.read(selectedWeekStartProvider.notifier).state =
                      startOfWeek(date);
                  if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
                    context.go('/review/weekly');
                  } else {
                    context.push('/review/weekly');
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildDateNav(context, ref, date, dayContext?.displayLabel),
              const SizedBox(height: AppSpacing.md),
              _buildSummary(statsAsync, insightsAsync, future),
              const SizedBox(height: AppSpacing.md),
              _buildChanges(insightsAsync, future),
              const SizedBox(height: AppSpacing.md),
              _buildCarryover(insightsAsync),
              const SizedBox(height: AppSpacing.md),
              _DailyReviewForm(key: ValueKey('review-form-$date'), date: date),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateNav(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    String? dayContextLabel,
  ) {
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
        if (dayContextLabel != null)
          _DayContextBadge(
            key: ValueKey('review-day-context-${isoDateString(date)}'),
            label: dayContextLabel,
          ),
        IconButton(
          key: const ValueKey('review-next-day'),
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => notifier.state = addDays(date, 1),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          key: const ValueKey('review-today'),
          onPressed: () => notifier.state = startOfDay(DateTime.now()),
          child: const Text('Today'),
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
      heading: 'Today / Day at a glance',
      emptyLabel: 'No planned items for this day.',
    );
  }

  Widget _buildChanges(AsyncValue<ReviewInsights> insights, bool future) {
    if (!insights.hasValue) return const SizedBox.shrink();
    return ReviewChangesSection(
      insights: insights.requireValue,
      future: future,
    );
  }

  Widget _buildCarryover(AsyncValue<ReviewInsights> insights) {
    if (!insights.hasValue) return const SizedBox.shrink();
    return ReviewCarryoverSection(
      heading: 'Tomorrow',
      items: insights.requireValue.carryover,
    );
  }
}

class _DayContextBadge extends StatelessWidget {
  final String label;

  const _DayContextBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      label: 'Day context: $label',
      container: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceSubtle,
          border: Border.all(color: tokens.outline),
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _DailyReviewForm extends ConsumerStatefulWidget {
  final DateTime date;

  const _DailyReviewForm({super.key, required this.date});

  @override
  ConsumerState<_DailyReviewForm> createState() => _DailyReviewFormState();
}

class _DailyReviewFormState extends ConsumerState<_DailyReviewForm> {
  final _noteController = TextEditingController();
  DailyReview? _existing;
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
          .getReviewForDate(widget.date);
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
          .saveDailyReview(
            DailyReview(
              id: old?.id ?? '',
              date: widget.date,
              reflection: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              // Preserve legacy fields even though the new UI no longer edits
              // them. Existing saved reviews must not lose information on edit.
              energyLevel: old?.energyLevel,
              productivityRating: old?.productivityRating,
              planningAccuracyRating: old?.planningAccuracyRating,
              wins: old?.wins ?? const [],
              improvements: old?.improvements ?? const [],
              createdAt: old?.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
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
          Text(
            'Anything worth remembering?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'What affected today’s plan, or what would you do differently next time?',
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
                  key: const ValueKey('review-note'),
                  controller: _noteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'What affected today’s plan, or what would you do differently next time?',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  key: const ValueKey('review-save'),
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
