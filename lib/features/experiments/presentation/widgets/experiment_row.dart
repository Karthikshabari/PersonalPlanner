import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/experiment.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../domain/experiment_dashboard.dart';
import '../../domain/experiment_progress.dart';
import '../../domain/kept_copy.dart';
import 'experiment_chart.dart';
import 'experiment_check_in_box.dart';
import 'experiment_end_panel.dart';
import 'experiment_past_check_ins.dart';
import 'experiment_progress_bar.dart';
import 'experiment_ui.dart';

/// One experiment on the Experiments card. (Named `ExperimentRowView` so it
/// does not clash with the Drift row class `ExperimentRow`.)
class ExperimentRowView extends StatelessWidget {
  const ExperimentRowView({super.key, required this.view, this.onShowKept});

  final ExperimentView view;

  /// Shows the Kept segment; called by "See it" on a kept concluded row.
  final VoidCallback? onShowKept;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final experiment = view.experiment;
    final concluded = experiment.status == ExperimentStatus.concluded;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < experimentNarrowWidth;
        return DecoratedBox(
          key: ValueKey('experiment-${experiment.id}'),
          decoration: BoxDecoration(
            color: styles.tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(ExperimentStyles.cardRadius),
          ),
          child: Padding(
            padding: EdgeInsets.all(narrow ? AppSpacing.lg : AppSpacing.xl),
            child: concluded
                ? _ConcludedBody(view: view, onShowKept: onShowKept)
                : _RunningBody(view: view),
          ),
        );
      },
    );
  }
}

/// Puts a 16 gap, a hairline and a 16 gap between major blocks.
Widget _blocks(List<Widget> blocks) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < blocks.length; i++) ...[
      if (i > 0) ...const [
        SizedBox(height: AppSpacing.lg),
        ExperimentHairline(),
        SizedBox(height: AppSpacing.lg),
      ],
      blocks[i],
    ],
  ],
);

class _RunningBody extends StatelessWidget {
  const _RunningBody({required this.view});

  final ExperimentView view;

  @override
  Widget build(BuildContext context) {
    final id = view.experiment.id;
    final progress = view.progress;
    final styles = ExperimentStyles.of(context);
    final started = view.today.compareTo(view.experiment.startDate) >= 0;
    final paceColor = !started
        ? styles.scheme.onSurface
        : progress.paceMin < 0
        ? styles.amber
        : styles.done;
    return _blocks([
      _Header(view: view),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressHeadline(view: view),
          const SizedBox(height: AppSpacing.md),
          ExperimentProgressBar(experimentId: id, progress: progress),
          const SizedBox(height: AppSpacing.lg),
          _StatRow(
            cells: [
              _Stat(
                key: ValueKey('experiment-pace-$id'),
                label: 'Pace',
                value: Text(
                  progress.paceLabel,
                  style: styles.statValue.copyWith(color: paceColor),
                ),
              ),
              _Stat(
                key: ValueKey('experiment-days-at-target-$id'),
                label: 'Days at your target',
                value: Text(
                  progress.daysAtTargetLabel,
                  style: styles.statValue,
                ),
              ),
              _Stat(
                key: ValueKey('experiment-check-ins-$id'),
                label: 'Check-ins',
                value: _CheckInStatistic(text: view.checkInStatistic),
              ),
            ],
          ),
          if (progress.hasTodayLine) ...[
            const SizedBox(height: AppSpacing.lg),
            _TodayStrip(id: id, progress: progress),
          ],
        ],
      ),
      ExperimentChart(view: view),
      if (view.showsEndPanel) ExperimentEndPanel(experiment: view.experiment),
      if (view.pendingDates.isNotEmpty)
        ExperimentCheckInBox(
          experimentId: id,
          pendingDates: view.pendingDates,
          missedCount: view.missedCount,
          dueToday: view.dueToday,
        ),
      ExperimentPastCheckIns(experimentId: id, checkIns: view.checkIns),
    ]);
  }
}

/// A concluded experiment: the outcome first, then the final result. The
/// chart and the written check-ins sit behind one "Show details" toggle.
class _ConcludedBody extends StatefulWidget {
  const _ConcludedBody({required this.view, this.onShowKept});

  final ExperimentView view;
  final VoidCallback? onShowKept;

  @override
  State<_ConcludedBody> createState() => _ConcludedBodyState();
}

class _ConcludedBodyState extends State<_ConcludedBody> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final experiment = view.experiment;
    final id = experiment.id;
    final progress = view.progress;
    final styles = ExperimentStyles.of(context);
    final outcome = experiment.outcome?.label;
    final completion = progress.totalMin > 0
        ? '${(progress.doneMin * 100 / progress.totalMin).round()}%'
        : '—';
    return _blocks([
      _Header(view: view),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outcome != null && outcome.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                Semantics(
                  label: 'Outcome: $outcome',
                  child: ExcludeSemantics(
                    child: ExperimentChip(
                      key: ValueKey('experiment-outcome-$id'),
                      text: outcome,
                      color: styles.accent,
                      textColor: styles.accentText,
                      leading: Icon(
                        Icons.check,
                        size: 14,
                        color: styles.accentText,
                      ),
                    ),
                  ),
                ),
                if (experiment.isRetired)
                  ExperimentChip(
                    key: ValueKey('experiment-retired-chip-$id'),
                    text: keptRetiredChip(experiment.retiredAt!),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            experiment.conclusionNote ?? 'No note added.',
            key: ValueKey('experiment-conclusion-note-$id'),
            style: styles.body,
          ),
          if (experiment.retireNote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(keptWhenRetiredLabel.toUpperCase(), style: styles.statLabel),
            const SizedBox(height: AppSpacing.xs),
            Text(
              experiment.retireNote!,
              key: ValueKey('experiment-retire-note-$id'),
              style: styles.body,
            ),
          ],
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressHeadline(view: view),
          const SizedBox(height: AppSpacing.md),
          ExperimentProgressBar(
            experimentId: id,
            progress: progress,
            concluded: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          _StatRow(
            cells: [
              _Stat(
                key: ValueKey('experiment-completion-$id'),
                label: 'Completion',
                value: Text(completion, style: styles.statValue),
              ),
              _Stat(
                key: ValueKey('experiment-days-at-target-$id'),
                label: 'Days at your target',
                value: Text(
                  progress.daysAtTargetLabel,
                  style: styles.statValue,
                ),
              ),
              _Stat(
                key: ValueKey('experiment-check-ins-$id'),
                label: 'Check-ins',
                value: _CheckInStatistic(text: view.checkInStatistic),
              ),
            ],
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentToggleRow(
            key: ValueKey('experiment-details-$id'),
            open: _showDetails,
            onPressed: () => setState(() => _showDetails = !_showDetails),
            leading: Text(
              _showDetails ? 'Hide details' : 'Show details',
              style: styles.sectionHeading,
            ),
          ),
          if (_showDetails) ...[
            const SizedBox(height: AppSpacing.md),
            ExperimentChart(view: view),
            if (view.checkIns.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              ExperimentPastCheckIns(
                experimentId: id,
                checkIns: view.checkIns,
                collapsible: false,
              ),
            ],
          ],
        ],
      ),
      if (experiment.isKept)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(
              keptNowUnderText(),
              key: ValueKey('experiment-now-kept-$id'),
              style: styles.note,
            ),
            ExperimentTextLink(
              key: ValueKey('experiment-see-kept-$id'),
              label: keptSeeIt,
              color: styles.accentText,
              onPressed: widget.onShowKept,
            ),
          ],
        ),
    ]);
  }
}

/// Name and status chip, the meta line, the extension line and the purpose.
class _Header extends StatelessWidget {
  const _Header({required this.view});

  final ExperimentView view;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final experiment = view.experiment;
    final id = experiment.id;
    final purpose = experiment.purpose;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(experiment.tagName, style: styles.cardTitle)),
            const SizedBox(width: AppSpacing.md),
            _StatusChip(text: view.progress.statusChip),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(_metaLine(experiment), style: styles.caption),
        if (view.extensionLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            view.extensionLine!,
            key: ValueKey('experiment-extension-$id'),
            style: styles.caption,
          ),
        ],
        if (purpose != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(purpose, style: styles.body),
        ],
      ],
    );
  }
}

/// "Oct 4 – Nov 7 · 60 min weekdays · 90 min weekends · Daily check-in".
String _metaLine(Experiment experiment) {
  String monthDay(String iso) => DateFormat('MMM d').format(parseIsoDate(iso));
  final frequency = switch (experiment.checkInEveryDays) {
    1 => 'Daily',
    7 => 'Weekly',
    _ => experimentFrequencyLabel(experiment.checkInEveryDays),
  };
  return '${monthDay(experiment.startDate)} – '
      '${monthDay(experiment.endDate)} · '
      '${experiment.weekdayTargetMin} min weekdays · '
      '${experiment.weekendTargetMin} min weekends · '
      '$frequency check-in';
}

/// The status chip. "Running · Day 7 of 35" shows an accent dot and
/// "Day 7 of 35"; any other status ("Concluded Oct 9", "Starts Oct 12") is a
/// plain neutral chip.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  static const _runningPrefix = 'Running · ';

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final running = text.startsWith(_runningPrefix);
    return ExperimentChip(
      text: running ? text.substring(_runningPrefix.length) : text,
      leading: running ? ExperimentDot(color: styles.accent) : null,
    );
  }
}

/// "20m of 1h expected so far" with the done value large.
class _ProgressHeadline extends StatelessWidget {
  const _ProgressHeadline({required this.view});

  final ExperimentView view;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final progress = view.progress;
    final id = view.experiment.id;
    final concluded = view.experiment.status == ExperimentStatus.concluded;
    final key = ValueKey('experiment-headline-$id');
    if (!concluded && progress.expectedMin == 0 && progress.doneMin == 0) {
      return Text(
        progress.headline,
        key: key,
        style: styles.body.copyWith(color: styles.muted),
      );
    }
    final done = formatMinutes(progress.doneMin);
    final rest = concluded
        ? ' of ${formatMinutes(progress.totalMin)} planned'
        : ' of ${formatMinutes(progress.expectedMin)} expected so far';
    return Semantics(
      label: concluded ? 'Done $done$rest' : progress.headline,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: done, style: styles.big),
            TextSpan(
              text: rest,
              style: styles.body.copyWith(color: styles.muted),
            ),
          ],
        ),
        key: key,
      ),
    );
  }
}

/// Three equal cells with hairline vertical dividers.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.cells});

  final List<_Stat> cells;

  @override
  Widget build(BuildContext context) {
    final divider = BorderSide(
      color: Theme.of(context).colorScheme.outlineVariant,
    );
    return Table(
      border: TableBorder(verticalInside: divider),
      children: [
        TableRow(
          children: [
            for (var i = 0; i < cells.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : AppSpacing.md,
                  right: i == cells.length - 1 ? 0 : AppSpacing.md,
                ),
                child: cells[i],
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: styles.statLabel),
        const SizedBox(height: AppSpacing.xs),
        value,
      ],
    );
  }
}

/// "4 written · 2 missed", the missed part in amber.
class _CheckInStatistic extends StatelessWidget {
  const _CheckInStatistic({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final parts = text.split(' · ');
    return Text.rich(
      TextSpan(
        style: styles.statValue,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const TextSpan(text: ' · '),
            TextSpan(
              text: parts[i],
              style: parts[i].endsWith(' missed')
                  ? TextStyle(color: styles.amber)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// A filled strip: today's done, still planned and target minutes, an amber
/// note when the plan is short, and the caption about today's target.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.id, required this.progress});

  final String id;
  final ExperimentProgress progress;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final hint = progress.shortfallHint;
    return Semantics(
      label: progress.todayLine,
      excludeSemantics: true,
      child: DecoratedBox(
        key: ValueKey('experiment-today-$id'),
        decoration: BoxDecoration(
          color: styles.strip,
          borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Today',
                    style: styles.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${formatMinutes(progress.todayDoneMin)} done',
                    style: styles.body,
                  ),
                  Text(
                    '${formatMinutes(progress.todayStillPlannedMin)} '
                    'still planned',
                    style: styles.body,
                  ),
                  Text(
                    progress.todayIsLeaveOrHoliday
                        ? 'Leave, no target'
                        : 'target ${formatMinutes(progress.todayTargetMin)}',
                    style: styles.body,
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: styles.amber,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        hint,
                        style: styles.caption.copyWith(color: styles.amber),
                      ),
                    ),
                  ],
                ),
              ],
              if (progress.showExtraLegendLine) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Today's target only counts against you once the day is "
                  'over.',
                  style: styles.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
