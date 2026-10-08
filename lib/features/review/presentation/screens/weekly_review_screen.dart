import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/weekly_review.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/review_draft.dart';
import '../../domain/weekly_review_draft.dart';
import '../../domain/weekly_review_history.dart';
import '../../domain/weekly_review_numbers.dart';
import '../../providers/review_providers.dart';
import '../../providers/weekly_review_draft_controller.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_snack_bar.dart';
import '../widgets/review_status_chip.dart';
import '../widgets/weekly_feeling_card.dart';
import '../widgets/weekly_glance_card.dart';
import '../widgets/weekly_mood_card.dart';
import '../widgets/weekly_next_week_tab.dart';
import '../widgets/weekly_note_line.dart';
import '../widgets/weekly_outcomes_card.dart';
import '../widgets/weekly_reasons_card.dart';
import '../widgets/weekly_reveal_card.dart';
import '../widgets/weekly_save_bar.dart';

/// Weekly review: a "Review" sub-tab and a "Next week (optional)" sub-tab
/// sharing one Save bar (spec 3.1).
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTab);
  final _scrollController = ScrollController();
  final _saveFocusNode = FocusNode(debugLabel: 'weekly-save');
  final _revealKey = GlobalKey();

  /// Content is at least 760 dp wide (two columns, Ctrl + Enter hint).
  bool _wide = true;

  /// Bumped on the first save of a week in this session: plays the reveal.
  int _revealToken = 0;

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scrollController.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  void _onMode(String mode, DateTime weekStart) {
    if (mode == 'overview') {
      openReviewPath(context, '/review/overview');
      return;
    }
    if (mode != 'daily') return;
    ref.read(selectedReviewDateProvider.notifier).state = weekStart;
    if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      context.go('/review');
    } else {
      context.push('/review');
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = startOfWeek(ref.watch(selectedWeekStartProvider));
    final daysAsync = ref.watch(weeklyDaysProvider(weekStart));
    final history =
        ref.watch(weeklyReviewHistoryProvider(weekStart)).value ??
        const <WeeklyHistoryWeek>[];
    final reviewAsync = ref.watch(weeklyReviewProvider(weekStart));
    final draft = ref.watch(weeklyReviewDraftProvider(weekStart));
    final tokens = AppThemeTokens.of(context);
    final future = weekStart.isAfter(startOfWeek(DateTime.now()));
    final numbers = daysAsync.hasValue
        ? computeWeeklyNumbers(daysAsync.requireValue)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Review'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600
                ? AppSpacing.md
                : AppSpacing.lg;
            final wide =
                math.min(constraints.maxWidth - 2 * padding, 1000.0) >= 760;
            _wide = wide;
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: true,
                ): () =>
                    _save(weekStart),
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  meta: true,
                ): () =>
                    _save(weekStart),
              },
              child: Focus(
                autofocus: true,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: _scrollController,
                        padding: EdgeInsets.all(padding),
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
                                      weekly: true,
                                      onChanged: (mode) =>
                                          _onMode(mode, weekStart),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  _buildHeader(weekStart, reviewAsync, future),
                                  const SizedBox(height: AppSpacing.sm),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TabBar(
                                      key: const ValueKey('weekly-subtabs'),
                                      controller: _tabs,
                                      isScrollable: true,
                                      tabAlignment: TabAlignment.start,
                                      tabs: const [
                                        Tab(text: 'Review'),
                                        Tab(text: 'Next week (optional)'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  if (_tabs.index == 0)
                                    _buildReviewTab(
                                      weekStart: weekStart,
                                      daysAsync: daysAsync,
                                      numbers: numbers,
                                      history: history,
                                      draft: draft,
                                      future: future,
                                      wide: wide,
                                      reviewAsync: reviewAsync,
                                    )
                                  else
                                    WeeklyNextWeekTab(
                                      key: ValueKey(
                                        'weekly-next-week-${isoDateString(weekStart)}',
                                      ),
                                      draft: draft,
                                      onChanged: ref
                                          .read(
                                            weeklyReviewDraftProvider(weekStart)
                                                .notifier,
                                          )
                                          .setNote,
                                      blockerLine:
                                          numbers?.blockerLine ??
                                          'No blockers recorded this week.',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    WeeklySaveBar(
                      draft: draft,
                      focusNode: _saveFocusNode,
                      onSave: () => _save(weekStart),
                      showShortcutHint: wide,
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

  Widget _buildHeader(
    DateTime weekStart,
    AsyncValue<WeeklyReview?> reviewAsync,
    bool future,
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
          '${DateFormat('MMM d').format(weekStart)} – '
          '${DateFormat('MMM d, yyyy').format(weekEnd)}',
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
        if (!future && reviewAsync.hasValue)
          ReviewStatusChip(
            key: const ValueKey('weekly-status-chip'),
            reviewed: reviewAsync.value != null,
            mood: reviewAsync.value?.mood,
            onPressed: _saveFocusNode.requestFocus,
          ),
      ],
    );
  }

  Widget _buildReviewTab({
    required DateTime weekStart,
    required AsyncValue<List<WeeklyDayInput>> daysAsync,
    required WeeklyNumbers? numbers,
    required List<WeeklyHistoryWeek> history,
    required WeeklyReviewDraft draft,
    required bool future,
    required bool wide,
    required AsyncValue<WeeklyReview?> reviewAsync,
  }) {
    if (daysAsync.hasError) {
      return ErrorPanel(message: friendlyErrorMessage(daysAsync.error!));
    }
    if (numbers == null) {
      return const AppSurface(child: LinearProgressIndicator());
    }
    final notifier = ref.read(weeklyReviewDraftProvider(weekStart).notifier);
    final note = fromLastWeekNote(history);
    final glance = WeeklyGlanceCard(numbers: numbers, future: future);
    final reasons = WeeklyReasonsCard(numbers: numbers);
    final outcomes = WeeklyOutcomesCard(rows: numbers.outcomeRows);
    final mood = WeeklyMoodCard(
      selected: draft.mood,
      enabled: draft.hydrated,
      onChanged: notifier.setMood,
      lastWeekHint: lastWeekMoodHint(history),
    );
    final feeling = WeeklyFeelingCard(
      // One text controller per week: a draft restored for week A must not
      // be shown through the field state of week B.
      key: ValueKey('weekly-feeling-card-${isoDateString(weekStart)}'),
      draft: draft,
      onChanged: notifier.setFeeling,
    );
    final reveal = KeyedSubtree(
      key: _revealKey,
      child: KeyedSubtree(
        key: const ValueKey('weekly-reveal'),
        child: WeeklyRevealCard(
          // A new state per week: a week opens in its final state and never
          // replays another week's animation.
          key: ValueKey('weekly-reveal-${isoDateString(weekStart)}'),
          revealed:
              draft.hydrated &&
              (reviewAsync.value?.mood != null ||
                  draft.saveStatus == ReviewSaveStatus.saved),
          mood: draft.savedMood,
          percent: numbers.percent,
          deltaText: weeklyDeltaText(
            percent: numbers.percent,
            previous: history,
          ),
          highlights: numbers.highlights,
          feeling: draft.savedFeeling,
          dots: weeklyDots(history),
          playToken: _revealToken,
        ),
      ),
    );
    const gap = SizedBox(height: AppSpacing.md);
    final top = <Widget>[
      if (note != null) ...[
        WeeklyNoteLine(
          key: const ValueKey('weekly-from-last-week'),
          heading: 'From last week',
          note: note,
        ),
        gap,
      ],
      glance,
      gap,
    ];
    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...top,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 29,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [reasons, gap, outcomes],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [mood, gap, feeling, gap, reveal],
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...top,
        mood,
        gap,
        feeling,
        gap,
        reveal,
        gap,
        reasons,
        gap,
        outcomes,
      ],
    );
  }

  Future<void> _save(DateTime weekStart) async {
    final ok = await ref
        .read(weeklyReviewDraftProvider(weekStart).notifier)
        .save();
    if (!mounted) return;
    if (!ok) {
      // `save` also returns false for "already saving / not hydrated"; only a
      // real write failure gets the error message.
      if (ref.read(weeklyReviewDraftProvider(weekStart)).saveStatus ==
          ReviewSaveStatus.failed) {
        showReviewSnackBar(
          context,
          'Couldn\'t save the review. Try again.',
          liftBy: 72,
        );
      }
      return;
    }
    ref.invalidate(weeklyReviewHistoryProvider);
    if (defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.lightImpact();
    }
    final firstReveal = ref.read(weeklyRevealPlayedProvider).add(weekStart);
    if (firstReveal) setState(() => _revealToken++);
    if (_tabs.index != 0) _tabs.index = 0;
    showReviewSnackBar(
      context,
      'Review saved',
      actionLabel: 'See in Overview',
      onAction: () {
        if (mounted) openReviewPath(context, '/review/overview');
      },
      liftBy: 72,
    );
    if (firstReveal && !_wide) _scrollToReveal();
  }

  /// Centres "Your week" after the first save on a narrow layout, once the
  /// Review tab is on screen; instant with reduced motion.
  void _scrollToReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _revealKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
      );
    });
  }
}
