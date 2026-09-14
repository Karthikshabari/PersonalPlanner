import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/analytics_models.dart';
import '../../providers/analytics_providers.dart';
import '../widgets/analytics_cards.dart';

/// The route and class name stay stable to avoid needless navigation churn;
/// the user-facing feature is Insights throughout.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWeek = ref.watch(selectedInsightsWeekProvider);
    final now = ref.watch(insightsNowProvider);
    final currentWeek = startOfWeek(now);
    final snapshot = ref.watch(insightsSnapshotProvider);
    final tokens = AppThemeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Insights'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          return ListView(
            padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: snapshot.when(
                    loading: () => const _InsightsLoading(),
                    error: (error, _) =>
                        ErrorPanel(message: friendlyErrorMessage(error)),
                    data: (value) => _InsightsContent(
                      snapshot: value,
                      compact: compact,
                      desktopWeekLayout: constraints.maxWidth >= 980,
                      selectedWeek: selectedWeek,
                      canGoForward: selectedWeek.isBefore(currentWeek),
                      onPrevious: () {
                        ref.read(selectedInsightsWeekProvider.notifier).state =
                            addDays(selectedWeek, -7);
                      },
                      onNext: () {
                        if (!selectedWeek.isBefore(currentWeek)) return;
                        ref.read(selectedInsightsWeekProvider.notifier).state =
                            addDays(selectedWeek, 7);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InsightsContent extends StatelessWidget {
  const _InsightsContent({
    required this.snapshot,
    required this.compact,
    required this.desktopWeekLayout,
    required this.selectedWeek,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
  });

  final InsightsSnapshot snapshot;
  final bool compact;
  final bool desktopWeekLayout;
  final DateTime selectedWeek;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InsightsSectionCard(
        key: const ValueKey('consistency-section'),
        title: 'Consistency',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConsistencyGrid(snapshot: snapshot, compact: compact),
            const SizedBox(height: AppSpacing.xl),
            StreakSummaryView(streaks: snapshot.streaks),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Leave, Holiday, and days without a plan stay neutral.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppThemeTokens.of(context).textMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      InsightsSectionCard(
        key: const ValueKey('this-week-section'),
        title: 'This Week',
        stackHeader: compact,
        headerTrailing: WeekNavigator(
          start: selectedWeek,
          canGoForward: canGoForward,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        child: ThisWeekSummary(snapshot: snapshot, desktop: desktopWeekLayout),
      ),
    ],
  );
}

class _InsightsLoading extends StatelessWidget {
  const _InsightsLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.huge),
      child: CircularProgressIndicator(),
    ),
  );
}
