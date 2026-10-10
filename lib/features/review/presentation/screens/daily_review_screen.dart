import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/daily_review.dart';
import '../../../../core/models/daily_stats.dart';
import '../../../../core/models/day_context.dart';
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
import '../../providers/review_warmup.dart';
import '../widgets/daily_glance_card.dart';
import '../widgets/review_equal_row.dart';
import '../widgets/review_layout.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_mood_card.dart';
import '../widgets/review_note_card.dart';
import '../widgets/review_save_bar.dart';
import '../widgets/review_snack_bar.dart';
import '../widgets/review_status_chip.dart';
import '../widgets/task_outcomes_card.dart';

/// Below this width the date row sits on its own line, with the Today button
/// and the reviewed badge underneath.
const double _compactHeaderWidth = 560;

class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({super.key});

  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen> {
  final _scrollController = ScrollController();
  final _saveFocusNode = FocusNode(debugLabel: 'review-save');
  final _warmup = ReviewWarmup();

  @override
  void initState() {
    super.initState();
    ref.listenManual(selectedReviewDateProvider, (_, _) => _warmNext());
    _warmNext();
  }

  /// After the frame that shows the selected day, load what is likely next
  /// (the days either side, the Weekly tab), so stepping there is instant and
  /// the neighbours never compete with the day on screen.
  void _warmNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmup.replace(
        ref,
        dailyReviewWarmTargets(ref.read(selectedReviewDateProvider)),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The screen listens to the day's data, never to the draft: each card
    // below listens to the slice of the draft it shows, so typing or picking
    // a rating rebuilds only that card.
    final date = startOfDay(ref.watch(selectedReviewDateProvider));
    final statsAsync = ref.watch(dailyStatsProvider(date));
    final insightsAsync = ref.watch(dailyReviewInsightsProvider(date));
    final outcomesAsync = ref.watch(taskOutcomesProvider(date));
    final reviewAsync = ref.watch(dailyReviewProvider(date));
    final dayContext = ref.watch(dayContextForDateProvider(date)).value;
    final tokens = AppThemeTokens.of(context);
    final today = startOfDay(DateTime.now());
    final future = date.isAfter(today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Review'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = ReviewLayout.isWide(constraints.maxWidth);
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
              child: Focus(
                autofocus: true,
                child: Column(
                  children: [
                    // The page and the bar are separate traversal groups: Tab
                    // sorts by on-screen position, and the long list runs
                    // under the bar's y range, which would otherwise make it
                    // hop to Save between every two controls.
                    Expanded(
                      child: FocusTraversalGroup(
                        child: ListView(
                          controller: _scrollController,
                          // The bar sits under the list, not over it, so the
                          // last card is never hidden (also with the keyboard).
                          padding: const EdgeInsets.all(
                            ReviewLayout.pagePadding,
                          ),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: ReviewLayout.maxContentWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: ReviewModeSwitcher(
                                        weekly: false,
                                        onChanged: (mode) =>
                                            _onMode(mode, date),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    _buildDateNav(
                                      context,
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
                                      future: future,
                                      isToday: date == today,
                                      wide: wide,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FocusTraversalGroup(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final facts = ref.watch(
                            reviewDraftProvider(date).select(
                              (d) => (
                                d.hydrated,
                                d.saveStatus,
                                d.differsFromSaved,
                              ),
                            ),
                          );
                          final (hydrated, saveStatus, differs) = facts;
                          return ReviewSaveBar(
                            // "Saved" is only true while nothing differs from
                            // what is stored.
                            status:
                                differs && saveStatus == ReviewSaveStatus.saved
                                ? ReviewSaveStatus.idle
                                : saveStatus,
                            enabled: hydrated && outcomesAsync.hasValue,
                            differsFromSaved: differs,
                            focusNode: _saveFocusNode,
                            onSave: () => _save(date),
                            showShortcutHint: wide,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onMode(String mode, DateTime date) {
    if (mode == 'overview') {
      openReviewPath(context, '/review/overview');
      return;
    }
    if (mode != 'weekly') return;
    ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(date);
    if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      context.go('/review/weekly');
    } else {
      context.push('/review/weekly');
    }
  }

  Widget _buildBody({
    required DateTime date,
    required AsyncValue<DailyStats> statsAsync,
    required AsyncValue<ReviewInsights> insightsAsync,
    required AsyncValue<List<TaskOutcomeRow>> outcomesAsync,
    required bool future,
    required bool isToday,
    required bool wide,
  }) {
    const gap = SizedBox(height: ReviewLayout.cardGap);
    final provider = reviewDraftProvider(date);
    final glance = _buildSummary(statsAsync, insightsAsync, future, isToday);
    // Each card with controls is its own traversal group, so in the two-column
    // layout Tab finishes one column's card before it starts the next.
    final outcomes = FocusTraversalGroup(
      child: TaskOutcomesCard(date: date, future: future, rows: outcomesAsync),
    );
    // Each card listens only to the draft fields it shows (`select`).
    final mood = FocusTraversalGroup(
      child: Consumer(
        builder: (context, ref, _) => ReviewMoodCard(
          selected: ref.watch(provider.select((d) => d.mood)),
          enabled: ref.watch(provider.select((d) => d.hydrated)),
          onChanged: ref.read(provider.notifier).setMood,
        ),
      ),
    );
    final note = FocusTraversalGroup(
      child: Consumer(
        builder: (context, ref, _) {
          // Only a re-hydration reloads the text field; typing does not.
          ref.watch(provider.select((d) => (d.hydrated, d.hydrationVersion)));
          return ReviewNoteCard(
            // One text controller per date: a draft restored for date A must
            // not be shown through the field state of date B.
            key: ValueKey('review-note-card-${isoDateString(date)}'),
            draft: ref.read(provider),
            onNoteChanged: ref.read(provider.notifier).setNote,
          );
        },
      ),
    );
    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day at a glance and the rating share a height; the two columns
          // split 3 : 2 here and below.
          ReviewEqualRow(
            spacing: ReviewLayout.cardGap,
            flexes: const [3, 2],
            children: [glance, mood],
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: outcomes),
              const SizedBox(width: ReviewLayout.cardGap),
              Expanded(flex: 2, child: note),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [glance, gap, outcomes, gap, mood, gap, note],
    );
  }

  Widget _buildDateNav(
    BuildContext context,
    DateTime date,
    String? dayContextLabel,
    AsyncValue<DailyReview?> reviewAsync,
    bool future,
  ) {
    final notifier = ref.read(selectedReviewDateProvider.notifier);
    final prev = IconButton(
      key: const ValueKey('review-prev-day'),
      tooltip: 'Previous day',
      icon: const Icon(Icons.chevron_left),
      onPressed: () => notifier.state = addDays(date, -1),
    );
    final next = IconButton(
      key: const ValueKey('review-next-day'),
      tooltip: 'Next day',
      icon: const Icon(Icons.chevron_right),
      onPressed: () => notifier.state = addDays(date, 1),
    );
    final dateText = Text(
      DateFormat('EEE, MMM d, yyyy').format(date),
      style: Theme.of(context).textTheme.titleLarge,
    );
    final badge = dayContextLabel == null
        ? null
        : _DayContextBadge(
            key: ValueKey('review-day-context-${isoDateString(date)}'),
            label: dayContextLabel,
          );
    final todayButton = OutlinedButton(
      key: const ValueKey('review-today'),
      onPressed: () => notifier.state = startOfDay(DateTime.now()),
      child: const Text('Today'),
    );
    final chip = !future && reviewAsync.hasValue
        ? ReviewStatusChip(
            key: const ValueKey('review-status-chip'),
            reviewed: reviewAsync.value != null,
            mood: reviewAsync.value?.mood,
            minTapHeight: 48,
            onPressed: _saveFocusNode.requestFocus,
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactHeaderWidth) {
          // Date on its own line (it wraps rather than overflow), the button
          // and the badges below it.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  prev,
                  Expanded(child: dateText),
                  next,
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [todayButton, ?badge, ?chip],
              ),
            ],
          );
        }
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            prev,
            dateText,
            ?badge,
            next,
            const SizedBox(width: AppSpacing.sm),
            todayButton,
            ?chip,
          ],
        );
      },
    );
  }

  Widget _buildSummary(
    AsyncValue<DailyStats> stats,
    AsyncValue<ReviewInsights> insights,
    bool future,
    bool isToday,
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
    return DailyGlanceCard(
      stats: stats.requireValue,
      insights: insights.requireValue,
      future: future,
      isToday: isToday,
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
        showReviewSnackBar(
          context,
          'Couldn\'t save the review. Try again.',
          liftBy: 72,
        );
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
      liftBy: 72,
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
