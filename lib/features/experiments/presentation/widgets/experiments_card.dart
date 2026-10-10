import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/models/experiment.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/experiment_dashboard.dart';
import '../../domain/kept_copy.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_row.dart';
import 'experiment_start_form.dart';
import 'experiment_ui.dart';
import 'kept_experiment_list.dart';

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
    final styles = ExperimentStyles.of(context);
    // The Insights screen pads 12 on narrow widths; 4 more makes 16.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: experimentColumnMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.xs : 0,
          ),
          child: Column(
            key: const ValueKey('experiments-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  Text(
                    'Experiments',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  _StartButton(
                    key: const ValueKey('experiments-start'),
                    accent: styles.accent,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
      ),
    ),
    onPressed: () => showExperimentStartForm(context),
    child: const Text('Start an experiment'),
  );
}

enum _Segment { running, kept, concluded }

class _Body extends StatefulWidget {
  const _Body({required this.dashboard});

  final ExperimentDashboard dashboard;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  // Local, not saved: the card always opens on Running.
  _Segment _segment = _Segment.running;

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final styles = ExperimentStyles.of(context);
    final mutedBody = styles.body.copyWith(color: styles.muted);
    if (dashboard.isEmpty) {
      return Text(
        'No experiments yet. Start one to follow how it is going here.',
        key: const ValueKey('experiments-empty'),
        style: mutedBody,
      );
    }
    final running = _segment == _Segment.running;
    final kept = _segment == _Segment.kept;
    final shown = kept
        ? const <ExperimentView>[]
        : [
            for (final view in dashboard.views)
              if (view.experiment.status ==
                  (running
                      ? ExperimentStatus.running
                      : ExperimentStatus.concluded))
                view,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Segment>(
              key: const ValueKey('experiments-filter'),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 44),
                textStyle: styles.label,
              ),
              segments: [
                ButtonSegment(
                  value: _Segment.running,
                  label: Text('Running (${dashboard.runningCount})'),
                ),
                ButtonSegment(
                  value: _Segment.kept,
                  label: Text(keptSegmentLabel(dashboard.keptCount)),
                ),
                ButtonSegment(
                  value: _Segment.concluded,
                  label: Text('Concluded (${dashboard.concludedCount})'),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (selection) =>
                  setState(() => _segment = selection.first),
            ),
          ),
        ),
        if (kept) ...const [
          SizedBox(height: AppSpacing.lg),
          KeptExperimentList(),
        ] else if (shown.isEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            running
                ? 'No running experiments.'
                : 'No concluded experiments yet.',
            key: const ValueKey('experiments-filter-empty'),
            style: mutedBody,
          ),
          if (running) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: _StartButton(
                key: const ValueKey('experiments-start-empty'),
                accent: styles.accent,
              ),
            ),
          ],
        ],
        for (final view in shown) ...[
          const SizedBox(height: AppSpacing.lg),
          ExperimentRowView(
            key: ValueKey('experiment-row-${view.experiment.id}'),
            view: view,
            onShowKept: () => setState(() => _segment = _Segment.kept),
          ),
        ],
      ],
    );
  }
}
