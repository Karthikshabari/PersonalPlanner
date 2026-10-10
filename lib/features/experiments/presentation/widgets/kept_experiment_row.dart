import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import '../../../analytics/providers/analytics_providers.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../domain/kept_copy.dart';
import '../../domain/kept_experiment.dart';
import 'experiment_ui.dart';
import 'kept_experiment_list.dart' show KeptRetiredEntry;
import 'kept_explain_panel.dart';
import 'kept_sheets.dart';
import 'kept_weekly_bars.dart';

/// The card container of a Kept row: the same surface, radius and padding as
/// `ExperimentRowView`.
class KeptCard extends StatelessWidget {
  const KeptCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < experimentNarrowWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: styles.tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(ExperimentStyles.cardRadius),
          ),
          child: Padding(
            padding: EdgeInsets.all(narrow ? AppSpacing.lg : AppSpacing.xl),
            child: child,
          ),
        );
      },
    );
  }
}

/// The text spans of [parts], with the bold pieces in semibold.
List<InlineSpan> keptSpans(List<KeptTextPart> parts, {Color? boldColor}) => [
  for (final part in parts)
    TextSpan(
      text: part.text,
      style: part.bold
          ? TextStyle(fontWeight: FontWeight.w600, color: boldColor)
          : null,
    ),
];

enum _KeptSheet { none, adjust, retire }

/// One kept experiment: the numbers of this week, the planned strip, the
/// weekly bars, an optional "how this is counted" panel and the Adjust target
/// and Retire sheets. Its UI state is local, so a bar tap or an open panel
/// rebuilds this row only.
class KeptExperimentRow extends ConsumerStatefulWidget {
  const KeptExperimentRow({
    super.key,
    required this.view,
    required this.onRetired,
  });

  final KeptExperimentView view;
  final void Function(KeptRetiredEntry entry) onRetired;

  @override
  ConsumerState<KeptExperimentRow> createState() => _KeptExperimentRowState();
}

class _KeptExperimentRowState extends ConsumerState<KeptExperimentRow> {
  String? _selectedWeekStart;
  bool _explainOpen = false;
  _KeptSheet _sheet = _KeptSheet.none;

  @override
  void didUpdateWidget(KeptExperimentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedWeekStart;
    if (selected != null &&
        !widget.view.bars.any((bar) => bar.weekStart == selected)) {
      _selectedWeekStart = null;
    }
  }

  void _planInDay() {
    final now = ref.read(insightsNowProvider);
    ref.read(selectedDateProvider.notifier).state = startOfDay(now);
    context.go('/day');
  }

  void _toggleSheet(_KeptSheet sheet) =>
      setState(() => _sheet = _sheet == sheet ? _KeptSheet.none : sheet);

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final id = view.experimentId;
    final styles = ExperimentStyles.of(context);
    final caution = view.chipTone == KeptTone.caution;
    final chipColor = caution ? styles.caution : styles.done;
    final planColor = switch (view.planState) {
      KeptPlanState.targetReached => styles.scheme.onSurface,
      KeptPlanState.reachesMinimum => styles.done,
      KeptPlanState.shortOfMinimum ||
      KeptPlanState.nothingPlanned => styles.caution,
    };
    final showPlanLink =
        view.planState == KeptPlanState.shortOfMinimum ||
        view.planState == KeptPlanState.nothingPlanned;
    final pending = view.pendingChange;
    final why = view.why;
    return KeptCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            key: ValueKey('kept-title-$id'),
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(view.name, style: styles.cardTitle),
                  const SizedBox(height: 2),
                  Text(view.subtitle, style: styles.subtitle),
                ],
              ),
              ExperimentChip(
                key: ValueKey('kept-chip-$id'),
                text: view.chipText,
                fontSize: 12.5,
                color: chipColor,
                fill: caution ? styles.cautionSoft : null,
              ),
            ],
          ),
          if (why != null) ...[
            const SizedBox(height: 10),
            Text.rich(
              key: ValueKey('kept-why-$id'),
              TextSpan(
                children: [
                  TextSpan(
                    text: keptWhyLabel.toUpperCase(),
                    style: styles.statLabel,
                  ),
                  const WidgetSpan(child: SizedBox(width: AppSpacing.sm)),
                  TextSpan(text: why, style: styles.body),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text.rich(
            key: ValueKey('kept-done-$id'),
            TextSpan(
              children: [
                TextSpan(
                  text: formatMinutes(view.doneMin),
                  style: styles.bigTight,
                ),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: SizedBox(width: 10),
                ),
                TextSpan(
                  text: keptThisWeekSuffix(formatMinutes(view.targetMin)),
                  style: styles.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          KeptProgressTrack(view: view),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 14,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LegendItem(
                swatch: _Swatch(color: styles.done),
                text: keptLegendDone,
              ),
              _LegendItem(
                swatch: _Swatch(color: styles.planned),
                text: keptLegendPlanned,
              ),
              _LegendItem(
                swatch: _Swatch(
                  color: styles.accent,
                  width: 2,
                  height: 11,
                  radius: 1,
                ),
                text: keptLegendExpected,
              ),
            ],
          ),
          if (pending != null) ...[
            const SizedBox(height: 6),
            Text.rich(
              key: ValueKey('kept-pending-$id'),
              TextSpan(
                style: styles.note,
                children: keptSpans(
                  keptPendingNoteParts(pending, formatMinutes),
                  boldColor: styles.scheme.onSurface,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: styles.strip,
              borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  Text.rich(
                    key: ValueKey('kept-plan-$id'),
                    TextSpan(
                      style: styles.body.copyWith(color: planColor),
                      children: keptSpans(
                        keptPlannedStripParts(
                          view.planState,
                          planned: view.plannedMin,
                          short: view.shortMin,
                          remaining: view.remainingMin,
                          formatDuration: formatMinutes,
                        ),
                      ),
                    ),
                  ),
                  if (showPlanLink)
                    ExperimentTextLink(
                      key: ValueKey('kept-plan-link-$id'),
                      label: keptPlanLink,
                      color: styles.accentText,
                      onPressed: _planInDay,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          KeptWeeklyBars(
            view: view,
            selectedWeekStart:
                _selectedWeekStart ??
                (view.bars.isEmpty ? '' : view.bars.last.weekStart),
            onSelect: (week) => setState(() => _selectedWeekStart = week),
          ),
          if (_explainOpen) ...[
            const SizedBox(height: AppSpacing.lg),
            const ExperimentHairline(),
            const SizedBox(height: AppSpacing.lg),
            KeptExplainPanel(view: view),
          ],
          if (_sheet != _KeptSheet.none) ...[
            const SizedBox(height: AppSpacing.lg),
            const ExperimentHairline(),
            const SizedBox(height: AppSpacing.lg),
            if (_sheet == _KeptSheet.adjust)
              KeptAdjustTargetSheet(
                view: view,
                onClose: () => setState(() => _sheet = _KeptSheet.none),
              )
            else
              KeptRetireSheet(
                view: view,
                onClose: () {
                  if (mounted) setState(() => _sheet = _KeptSheet.none);
                },
                onRetired: widget.onRetired,
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExperimentTextLink(
                key: ValueKey('kept-explain-toggle-$id'),
                label: keptExplainToggle(_explainOpen),
                onPressed: () => setState(() => _explainOpen = !_explainOpen),
              ),
              ExperimentTextLink(
                key: ValueKey('kept-adjust-$id'),
                label: keptAdjustLink,
                onPressed: () => _toggleSheet(_KeptSheet.adjust),
              ),
              ExperimentTextLink(
                key: ValueKey('kept-retire-$id'),
                label: keptRetireLink,
                onPressed: () => _toggleSheet(_KeptSheet.retire),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    this.width = 8,
    this.height = 8,
    this.radius = 2,
  });

  final Color color;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.swatch, required this.text});

  final Widget swatch;
  final String text;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: styles.caption)),
      ],
    );
  }
}

/// The 8px track: the done fill, the planned segment and the 2×16 tick that
/// marks where the week should be by today.
class KeptProgressTrack extends StatelessWidget {
  const KeptProgressTrack({super.key, required this.view});

  final KeptExperimentView view;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final id = view.experimentId;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final doneW = view.doneFraction * w;
        final plannedW = math.max(0.0, view.plannedEndFraction * w - doneW);
        final tickLeft = (view.tickFraction * w - 1).clamp(0.0, w - 2);
        return SizedBox(
          height: 16,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ColoredBox(
                    color: styles.scheme.surfaceContainerHighest,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: doneW,
                          child: ColoredBox(
                            key: ValueKey('kept-done-fill-$id'),
                            color: styles.done,
                          ),
                        ),
                        if (plannedW > 0)
                          Positioned(
                            left: doneW,
                            top: 0,
                            bottom: 0,
                            width: plannedW,
                            child: ColoredBox(
                              key: ValueKey('kept-planned-segment-$id'),
                              color: styles.planned,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: tickLeft,
                top: 0,
                width: 2,
                height: 16,
                child: DecoratedBox(
                  key: ValueKey('kept-tick-$id'),
                  decoration: BoxDecoration(
                    color: styles.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
