import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../experiments/presentation/widgets/experiments_card.dart';
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
                    loading: () {
                      // The snapshot from the last visit, only while it is
                      // still exactly what a fresh calculation would return:
                      // shown in the first frame, before the stream delivers
                      // its (identical) first value. Read, not watched, so a
                      // write while Insights is open does not rebuild twice.
                      final instant = ref.read(insightsCachedSnapshotProvider);
                      return instant == null
                          ? const _InsightsLoading()
                          : _InsightsContent(
                              snapshot: instant,
                              compact: compact,
                            );
                    },
                    error: (error, _) =>
                        ErrorPanel(message: friendlyErrorMessage(error)),
                    data: (value) =>
                        _InsightsContent(snapshot: value, compact: compact),
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
  const _InsightsContent({required this.snapshot, required this.compact});

  final InsightsSnapshot snapshot;
  final bool compact;

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
      ExperimentsCard(compact: compact),
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
