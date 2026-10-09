import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show InsightsSectionCard;
import '../../domain/experiment_dashboard.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_row.dart';
import 'experiment_start_form.dart';

/// The Experiments card of Insights (ED25). It shows the dashboard provider's
/// value, else the last cached dashboard, else a fixed-height placeholder with
/// no spinner (ED39, ED42), so returning to Insights never flashes a loading
/// state and a reload replaces numbers in place.
class ExperimentsCard extends ConsumerWidget {
  const ExperimentsCard({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(experimentDashboardProvider);
    final Widget body;
    if (async.hasError) {
      body = ErrorPanel(
        message: friendlyErrorMessage(async.error!),
        compact: true,
        onRetry: () => ref.invalidate(experimentDashboardProvider),
      );
    } else {
      final dashboard =
          async.value ?? ref.read(experimentDashboardCacheProvider)?.dashboard;
      body = dashboard == null
          ? const SizedBox(key: ValueKey('experiments-placeholder'), height: 96)
          : _Body(dashboard: dashboard);
    }
    return InsightsSectionCard(
      key: const ValueKey('experiments-section'),
      title: 'Experiments',
      stackHeader: compact,
      headerTrailing: FilledButton(
        key: const ValueKey('experiments-start'),
        onPressed: () => showExperimentStartForm(context),
        child: const Text('Start an experiment'),
      ),
      child: body,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.dashboard});

  final ExperimentDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.isEmpty) {
      return Text(
        'No experiments yet. Start one to follow how it is going here.',
        key: const ValueKey('experiments-empty'),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppThemeTokens.of(context).textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${dashboard.runningCount} running · '
          '${dashboard.concludedCount} concluded',
          key: const ValueKey('experiments-counts'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppThemeTokens.of(context).textSecondary),
        ),
        for (final view in dashboard.views) ...[
          const SizedBox(height: AppSpacing.md),
          ExperimentRowView(
            key: ValueKey('experiment-row-${view.experiment.id}'),
            view: view,
          ),
        ],
      ],
    );
  }
}
