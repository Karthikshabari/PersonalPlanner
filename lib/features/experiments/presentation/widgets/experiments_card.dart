import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/models/experiment.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/experiment_dashboard.dart';
import '../../domain/kept_copy.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_actions_menu.dart'
    show experimentDeletedLine, experimentUndoDeleteFailed;
import 'experiment_row.dart';
import 'experiment_start_form.dart';
import 'experiment_ui.dart';
import 'kept_experiment_list.dart';
import 'kept_experiment_row.dart' show KeptCard;

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

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.dashboard});

  final ExperimentDashboard dashboard;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  // Local, not saved: the card opens on Running, unless the Inbox asked to see
  // one experiment (`experimentFocusProvider`).
  _Segment _segment = _Segment.running;

  bool _undoing = false;

  /// Undoes the delete shown in the "Deleted ... Undo" line; the line goes
  /// away either way.
  Future<void> _undoDelete() async {
    final entry = ref.read(experimentDeletedProvider);
    if (entry == null || _undoing) return;
    _undoing = true;
    final repository = ref.read(experimentRepositoryProvider);
    final deleted = ref.read(experimentDeletedProvider.notifier);
    try {
      await repository.restoreExperiment(
        entry.experimentId,
        expectedRevision: entry.revision,
      );
    } catch (_) {
      if (mounted) showAppToast(context, experimentUndoDeleteFailed);
    } finally {
      _undoing = false;
      if (deleted.state == entry) deleted.state = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _applyFocus(ref.read(experimentFocusProvider), inInit: true);
  }

  /// Opens the segment the experiment is in, scrolls its row into view and
  /// clears the request. An experiment that is not on the dashboard (it can
  /// not be reached from here) just clears the request.
  void _applyFocus(String? id, {bool inInit = false}) {
    if (id == null) return;
    ExperimentView? target;
    for (final view in widget.dashboard.views) {
      if (view.experiment.id == id) target = view;
    }
    final segment = target == null
        ? null
        : target.experiment.status == ExperimentStatus.running
        ? _Segment.running
        : target.experiment.isKept
        ? _Segment.kept
        : _Segment.concluded;
    if (segment != null) {
      if (inInit) {
        _segment = segment;
      } else {
        setState(() => _segment = segment);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(experimentFocusProvider.notifier).state = null;
      if (segment == null) return;
      final row = _findRow(
        segment == _Segment.kept ? 'kept-row-$id' : 'experiment-row-$id',
      );
      if (row != null) Scrollable.ensureVisible(row, alignment: 0.05);
    });
  }

  /// The element of the row keyed [key] under this card, if it is built.
  BuildContext? _findRow(String key) {
    BuildContext? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == ValueKey(key)) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    // A request made while the card is already shown.
    ref.listen(experimentFocusProvider, (_, next) => _applyFocus(next));
    final dashboard = widget.dashboard;
    final styles = ExperimentStyles.of(context);
    final mutedBody = styles.body.copyWith(color: styles.muted);
    final deleted = ref.watch(experimentDeletedProvider);
    final deletedLine = deleted == null
        ? null
        : _DeletedLine(
            key: ValueKey('experiment-deleted-${deleted.experimentId}'),
            entry: deleted,
            onUndo: _undoDelete,
          );
    if (dashboard.isEmpty) {
      final empty = Text(
        'No experiments yet. Start one to follow how it is going here.',
        key: const ValueKey('experiments-empty'),
        style: mutedBody,
      );
      return deletedLine == null
          ? empty
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                deletedLine,
                const SizedBox(height: AppSpacing.lg),
                empty,
              ],
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
        if (deletedLine != null) ...[
          const SizedBox(height: AppSpacing.lg),
          deletedLine,
        ],
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

/// "Deleted {name}. Undo", the inline line that replaces a deleted row.
class _DeletedLine extends StatelessWidget {
  const _DeletedLine({super.key, required this.entry, required this.onUndo});

  final ExperimentDeletedEntry entry;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return KeptCard(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          Text(experimentDeletedLine(entry.name), style: styles.note),
          ExperimentTextLink(
            key: ValueKey('experiment-undo-delete-${entry.experimentId}'),
            label: keptUndo,
            color: styles.accentText,
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}
