import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../day_context/providers/day_context_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/review_draft.dart';
import '../../domain/review_insights.dart';
import '../../domain/task_outcome.dart';
import '../../providers/review_draft_controller.dart';
import '../../providers/review_providers.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_mood_card.dart';
import '../widgets/review_note_card.dart';
import '../widgets/review_save_button.dart';
import '../widgets/review_snack_bar.dart';
import '../widgets/review_sections.dart';
import '../widgets/review_status_chip.dart';
import '../widgets/review_unsaved_hint.dart';
import '../widgets/task_outcomes_card.dart';

class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({super.key});

  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen> {
  final _scrollController = ScrollController();
  final _saveButtonKey = GlobalKey();
  final _saveFocusNode = FocusNode(debugLabel: 'review-save');

  @override
  void dispose() {
    _scrollController.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = startOfDay(ref.watch(selectedReviewDateProvider));
    final statsAsync = ref.watch(dailyStatsProvider(date));
    final insightsAsync = ref.watch(dailyReviewInsightsProvider(date));
    final outcomesAsync = ref.watch(taskOutcomesProvider(date));
    final reviewAsync = ref.watch(dailyReviewProvider(date));
    final draft = ref.watch(reviewDraftProvider(date));
    final notifier = ref.read(reviewDraftProvider(date).notifier);
    final dayContext = ref.watch(dayContextForDateProvider(date)).value;
    final tokens = AppThemeTokens.of(context);
    final future = date.isAfter(startOfDay(DateTime.now()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Review'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final listView = ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.all(
                    constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.lg,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ReviewModeSwitcher(
                                weekly: false,
                                onChanged: (mode) {
                                  if (mode == 'overview') {
                                    openReviewPath(context, '/review/overview');
                                    return;
                                  }
                                  if (mode != 'weekly') return;
                                  ref
                                      .read(selectedWeekStartProvider.notifier)
                                      .state = startOfWeek(
                                    date,
                                  );
                                  if (isDesktopWidth(
                                    MediaQuery.sizeOf(context).width,
                                  )) {
                                    context.go('/review/weekly');
                                  } else {
                                    context.push('/review/weekly');
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _buildDateNav(
                              context,
                              ref,
                              date,
                              dayContext?.displayLabel,
                              reviewAsync,
                              future,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _buildBody(
                              date: date,
                              statsAsync: statsAsync,
                              insightsAsync: insightsAsync,
                              outcomesAsync: outcomesAsync,
                              draft: draft,
                              notifier: notifier,
                              future: future,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): () =>
                        _save(date),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      meta: true,
                    ): () =>
                        _save(date),
                  },
                  child: Focus(autofocus: true, child: listView),
                );
              },
            ),
            if (draft.differsFromSaved)
              const Positioned(
                left: 0,
                right: 0,
                bottom: AppSpacing.md,
                child: Center(
                  child: ReviewUnsavedPill(
                    key: ValueKey('review-unsaved-pinned'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required DateTime date,
    required AsyncValue<DailyStats> statsAsync,
    required AsyncValue<ReviewInsights> insightsAsync,
    required AsyncValue<List<TaskOutcomeRow>> outcomesAsync,
    required ReviewDraft draft,
    required ReviewDraftController notifier,
    required bool future,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        const gap = SizedBox(height: AppSpacing.md);
        final glance = _buildSummary(statsAsync, insightsAsync, future);
        final outcomes = TaskOutcomesCard(
          date: date,
          future: future,
          rows: outcomesAsync,
          draft: draft,
        );
        final mood = ReviewMoodCard(
          selected: draft.mood,
          enabled: draft.hydrated,
          onChanged: notifier.setMood,
        );
        final note = ReviewNoteCard(
          // One text controller per date: a draft restored for date A must not
          // be shown through the field state of date B.
          key: ValueKey('review-note-card-${isoDateString(date)}'),
          draft: draft,
          onNoteChanged: notifier.setNote,
          showShortcutHint: wide,
          saveButton: KeyedSubtree(
            key: _saveButtonKey,
            child: _buildSaveButton(date, draft, outcomesAsync),
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 29,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [glance, gap, outcomes],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [mood, gap, note],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [glance, gap, outcomes, gap, mood, gap, note],
        );
      },
    );
  }

  Widget _buildDateNav(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    String? dayContextLabel,
    AsyncValue<DailyReview?> reviewAsync,
    bool future,
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
        if (!future && reviewAsync.hasValue)
          ReviewStatusChip(
            key: const ValueKey('review-status-chip'),
            reviewed: reviewAsync.value != null,
            mood: reviewAsync.value?.mood,
            onPressed: _revealSave,
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

  Widget _buildSaveButton(
    DateTime date,
    ReviewDraft draft,
    AsyncValue<List<TaskOutcomeRow>> outcomesAsync,
  ) {
    return ReviewSaveButton(
      // "Saved" is only true while nothing differs from what is stored.
      status:
          draft.differsFromSaved && draft.saveStatus == ReviewSaveStatus.saved
          ? ReviewSaveStatus.idle
          : draft.saveStatus,
      enabled: draft.hydrated && outcomesAsync.hasValue,
      focusNode: _saveFocusNode,
      onPressed: () => _save(date),
    );
  }

  Future<void> _save(DateTime date) async {
    final rows = ref.read(taskOutcomesProvider(date)).value;
    if (rows == null) return;
    final ok = await ref
        .read(reviewDraftProvider(date).notifier)
        .save(rows: rows);
    if (!mounted) return;
    if (!ok) {
      // `save` also returns false for "already saving / not hydrated"; only a
      // real write failure gets the error message.
      if (ref.read(reviewDraftProvider(date)).saveStatus ==
          ReviewSaveStatus.failed) {
        showReviewSnackBar(context, 'Couldn\'t save the review. Try again.');
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.lightImpact();
    }
    showReviewSnackBar(
      context,
      'Review saved',
      actionLabel: 'See in Overview',
      onAction: () {
        if (mounted) openReviewPath(context, '/review/overview');
      },
    );
  }

  Future<void> _revealSave() async {
    final target = _saveButtonKey.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
    if (mounted) _saveFocusNode.requestFocus();
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
