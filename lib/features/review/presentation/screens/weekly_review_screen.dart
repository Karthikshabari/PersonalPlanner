import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/models/weekly_review.dart';
import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../domain/review_draft.dart';
import '../../domain/weekly_review_history.dart';
import '../../domain/weekly_review_numbers.dart';
import '../../providers/review_providers.dart';
import '../../providers/review_warmup.dart';
import '../../providers/weekly_review_draft_controller.dart';
import '../widgets/review_equal_row.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/review_search_results.dart';
import '../widgets/review_snack_bar.dart';
import '../widgets/review_status_chip.dart';
import '../widgets/weekly_empty_card.dart';
import '../widgets/weekly_feeling_card.dart';
import '../widgets/weekly_glance_card.dart';
import '../widgets/weekly_mood_card.dart';
import '../widgets/weekly_next_week_tab.dart';
import '../widgets/weekly_note_line.dart';
import '../widgets/weekly_outcomes_card.dart';
import '../widgets/weekly_reasons_card.dart';
import '../widgets/weekly_reveal_card.dart';
import '../widgets/weekly_save_bar.dart';

/// Below this width the buttons and the reviewed badge sit under the week
/// label instead of beside it.
const double _compactHeaderWidth = 560;

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
  final _warmup = ReviewWarmup();
  PageSearchController? _search;

  /// Content is at least 760 dp wide (two columns, Ctrl + Enter hint).
  bool _wide = true;

  /// Bumped on the first save of a week in this session: plays the reveal.
  int _revealToken = 0;

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(selectedWeekStartProvider, (_, _) => _warmNext());
    _warmNext();
  }

  /// After the frame that shows the selected week, load what is likely next
  /// (the weeks either side, the Daily tab), so stepping there is instant and
  /// the neighbours never compete with the week on screen.
  void _warmNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmup.replace(
        ref,
        weeklyReviewWarmTargets(ref.read(selectedWeekStartProvider)),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _search = PageSearchScope.maybeOf(context);
    _search?.scrollPosition = () =>
        _scrollController.hasClients ? _scrollController.position : null;
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
      openReviewPath(context, '/review/overview?tab=weekly');
      return;
    }
    if (mode != 'daily') return;
    ref.read(selectedReviewDateProvider.notifier).state = dailyDateForWeek(
      weekStart,
      ref.read(insightsNowProvider),
    );
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
    final tokens = AppThemeTokens.of(context);
    ref.watch(reviewRolloverProvider);
    final today = ref.watch(insightsNowProvider.select(startOfDay));
    final future = weekStart.isAfter(startOfWeek(today));
    final numbers = daysAsync.hasValue
        ? computeWeeklyNumbers(daysAsync.requireValue)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const PageSearchTitle('Weekly Review'),
        actions: const [PageSearchAction(), SyncStatusAction()],
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
            final inlineHeader =
                constraints.maxWidth - 2 * padding >= _compactHeaderWidth;
            final Widget tab = _tabs.index == 0
                ? _buildReviewTab(
                    weekStart: weekStart,
                    daysAsync: daysAsync,
                    numbers: numbers,
                    history: history,
                    future: future,
                    wide: wide,
                    reviewAsync: reviewAsync,
                  )
                // Only this tab follows every edit of the draft (its preview
                // shows the note as typed).
                : Consumer(
                    builder: (context, ref, _) => WeeklyNextWeekTab(
                      key: ValueKey(
                        'weekly-next-week-${isoDateString(weekStart)}',
                      ),
                      draft: ref.watch(weeklyReviewDraftProvider(weekStart)),
                      onChanged: ref
                          .read(weeklyReviewDraftProvider(weekStart).notifier)
                          .setNote,
                      blockerLine:
                          numbers?.blockerLine ??
                          'No blockers recorded this week.',
                    ),
                  );
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
                    // The mode switcher, the week and its arrows stay under the
                    // app bar while the page scrolls.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        AppSpacing.sm,
                        padding,
                        0,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ReviewModeSwitcher(
                                  weekly: true,
                                  onChanged: (mode) => _onMode(mode, weekStart),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _buildHeader(
                                  weekStart,
                                  today,
                                  reviewAsync,
                                  future,
                                  inline: inlineHeader,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                                  if (!inlineHeader) ...[
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.xs,
                                      children: _headerActions(
                                        today,
                                        reviewAsync,
                                        future,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
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
                                  _withSearch(tab),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    HideWhileReviewSearch(
                      search: _search,
                      child: Consumer(
                        builder: (context, ref, _) {
                          final provider = weeklyReviewDraftProvider(weekStart);
                          // The bar shows only these three facts, so a
                          // keystroke that changes none of them skips it.
                          ref.watch(
                            provider.select(
                              (d) => (
                                d.hydrated,
                                d.saveStatus,
                                d.differsFromSaved,
                              ),
                            ),
                          );
                          return WeeklySaveBar(
                            draft: ref.read(provider),
                            future: future,
                            stored: reviewAsync.value?.mood != null,
                            focusNode: _saveFocusNode,
                            onSave: () => _save(weekStart),
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

  /// While a search has a query the tab content is hidden, not removed, so
  /// drafts, text fields and scroll state survive; the results take its place.
  Widget _withSearch(Widget tab) {
    final search = _search;
    if (search == null) return tab;
    return ValueListenableBuilder<String>(
      valueListenable: search.needle,
      child: tab,
      builder: (context, needle, tab) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Visibility(visible: needle.isEmpty, maintainState: true, child: tab!),
          if (needle.isNotEmpty)
            ReviewSearchResults(
              needle: needle,
              weekly: true,
              onOpen: _openSearchWeek,
            ),
        ],
      ),
    );
  }

  void _openSearchWeek(DateTime weekStart) {
    ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(weekStart);
    _search?.close(restoreScroll: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  /// The arrows around the week label, which wraps rather than let an arrow
  /// drop to another line. Inline (wide) the buttons follow on the same row.
  Widget _buildHeader(
    DateTime weekStart,
    DateTime today,
    AsyncValue<WeeklyReview?> reviewAsync,
    bool future, {
    required bool inline,
  }) {
    final notifier = ref.read(selectedWeekStartProvider.notifier);
    final weekEnd = addDays(weekStart, 6);
    final label = Text(
      '${DateFormat('MMM d').format(weekStart)} – '
      '${DateFormat('MMM d, yyyy').format(weekEnd)}',
      style: Theme.of(context).textTheme.titleLarge,
    );
    final nav = Row(
      mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
      children: [
        IconButton(
          key: const ValueKey('week-prev'),
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left, semanticLabel: 'Previous week'),
          onPressed: () => notifier.state = addDays(weekStart, -7),
        ),
        inline ? Flexible(child: label) : Expanded(child: label),
        IconButton(
          key: const ValueKey('week-next'),
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right, semanticLabel: 'Next week'),
          onPressed: () => notifier.state = addDays(weekStart, 7),
        ),
      ],
    );
    if (!inline) return nav;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [nav, ..._headerActions(today, reviewAsync, future)],
    );
  }

  /// "This Week" and the reviewed badge.
  List<Widget> _headerActions(
    DateTime today,
    AsyncValue<WeeklyReview?> reviewAsync,
    bool future,
  ) {
    final notifier = ref.read(selectedWeekStartProvider.notifier);
    return [
      OutlinedButton(
        key: const ValueKey('week-this-week'),
        onPressed: () => notifier.state = startOfWeek(today),
        child: const Text('This Week'),
      ),
      if (!future && reviewAsync.hasValue)
        ReviewStatusChip(
          key: const ValueKey('weekly-status-chip'),
          reviewed: reviewAsync.value != null,
          mood: reviewAsync.value?.mood,
          onPressed: _saveFocusNode.requestFocus,
        ),
    ];
  }

  Widget _buildReviewTab({
    required DateTime weekStart,
    required AsyncValue<List<WeeklyDayInput>> daysAsync,
    required WeeklyNumbers? numbers,
    required List<WeeklyHistoryWeek> history,
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
    final provider = weeklyReviewDraftProvider(weekStart);
    final notifier = ref.read(provider.notifier);
    final note = fromLastWeekNote(history);
    // Nothing planned, nothing reviewed yet: one card instead of three empty
    // ones.
    final empty =
        !future &&
        reviewAsync.hasValue &&
        reviewAsync.value == null &&
        numbers.total == 0 &&
        !numbers.allBreak;
    final glance = empty
        ? WeeklyEmptyCard(onOpenWeek: () => _openWeek(weekStart))
        : WeeklyGlanceCard(numbers: numbers, future: future);
    final reasons = WeeklyReasonsCard(numbers: numbers);
    final outcomes = WeeklyOutcomesCard(rows: numbers.outcomeRows);
    final lastWeekHint = lastWeekMoodHint(history);
    // Each card listens only to the draft fields it shows (`select`), so an
    // edit rebuilds the card it belongs to and nothing else.
    final mood = Consumer(
      builder: (context, ref, _) => WeeklyMoodCard(
        selected: ref.watch(provider.select((d) => d.mood)),
        chosen: ref.watch(provider.select((d) => d.moodChosen)),
        enabled: ref.watch(provider.select((d) => d.hydrated)),
        onChanged: notifier.setMood,
        lastWeekHint: lastWeekHint,
      ),
    );
    final feeling = Consumer(
      builder: (context, ref, _) {
        // Only a re-hydration reloads the text field; typing does not.
        ref.watch(provider.select((d) => (d.hydrated, d.hydrationVersion)));
        return WeeklyFeelingCard(
          // One text controller per week: a draft restored for week A must
          // not be shown through the field state of week B.
          key: ValueKey('weekly-feeling-card-${isoDateString(weekStart)}'),
          draft: ref.read(provider),
          onChanged: notifier.setFeeling,
        );
      },
    );
    final deltaText = weeklyDeltaText(
      percent: numbers.percent,
      previous: history,
    );
    final dots = weeklyDots(history);
    final reveal = KeyedSubtree(
      key: _revealKey,
      child: KeyedSubtree(
        key: const ValueKey('weekly-reveal'),
        child: Consumer(
          builder: (context, ref, _) {
            final saved = ref.watch(
              provider.select(
                (d) => (
                  d.hydrated,
                  d.saveStatus == ReviewSaveStatus.saved,
                  d.savedMood,
                  d.savedFeeling,
                ),
              ),
            );
            return WeeklyRevealCard(
              // A new state per week: a week opens in its final state and
              // never replays another week's animation.
              key: ValueKey('weekly-reveal-${isoDateString(weekStart)}'),
              revealed:
                  saved.$1 && (reviewAsync.value?.mood != null || saved.$2),
              mood: saved.$3,
              percent: numbers.percent,
              deltaText: deltaText,
              highlights: numbers.highlights,
              feeling: saved.$4,
              dots: dots,
              playToken: _revealToken,
            );
          },
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
          if (empty)
            ReviewEqualRow(spacing: AppSpacing.md, children: [mood, reveal])
          else ...[
            ReviewEqualRow(spacing: AppSpacing.md, children: [reasons, mood]),
            gap,
            ReviewEqualRow(
              spacing: AppSpacing.md,
              children: [outcomes, reveal],
            ),
          ],
          gap,
          feeling,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...top,
        if (!empty) ...[reasons, gap, outcomes, gap],
        mood,
        gap,
        reveal,
        gap,
        feeling,
      ],
    );
  }

  /// Opens Week on this week, on today when the week has it.
  void _openWeek(DateTime weekStart) {
    ref.read(selectedDateProvider.notifier).state = dailyDateForWeek(
      weekStart,
      ref.read(insightsNowProvider),
    );
    context.go('/week');
  }

  Future<void> _save(DateTime weekStart) async {
    // The Save bar is off for a future week and hidden during a search; the
    // keyboard shortcut must not reach past either.
    final searching = _search?.needle.value.isNotEmpty ?? false;
    final future = weekStart.isAfter(
      startOfWeek(ref.read(insightsNowProvider)),
    );
    if (future || searching) return;
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
    ref.invalidate(reviewOverviewWeekWindowProvider);
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
        if (mounted) openReviewPath(context, '/review/overview?tab=weekly');
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
