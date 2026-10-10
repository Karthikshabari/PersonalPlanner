import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/experiment_check_in.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import 'experiment_ui.dart';

/// The written check-ins of one experiment, newest slot first, behind a
/// "Past check-ins" toggle (ED31). There is no edit or delete control: a
/// check-in is never changed once it is written.
///
/// With [collapsible] false the toggle is replaced by a heading and the list
/// is always shown (the concluded card's details).
class ExperimentPastCheckIns extends StatefulWidget {
  const ExperimentPastCheckIns({
    super.key,
    required this.experimentId,
    required this.checkIns,
    this.collapsible = true,
  });

  final String experimentId;

  /// Newest slot first.
  final List<ExperimentCheckIn> checkIns;

  final bool collapsible;

  @override
  State<ExperimentPastCheckIns> createState() => _ExperimentPastCheckInsState();
}

class _ExperimentPastCheckInsState extends State<ExperimentPastCheckIns> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.experimentId;
    final styles = ExperimentStyles.of(context);
    final count = widget.checkIns.length;
    final showList = !widget.collapsible || _open;
    final title = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Past check-ins', style: styles.sectionHeading),
        ExperimentChip(key: ValueKey('checkin-past-count-$id'), text: '$count'),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.collapsible)
          ExperimentToggleRow(
            key: ValueKey('checkin-past-$id'),
            open: _open,
            onPressed: () => setState(() => _open = !_open),
            leading: title,
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
        if (showList)
          if (widget.checkIns.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No check-ins written yet.',
                key: ValueKey('checkin-past-empty-$id'),
                style: styles.body.copyWith(color: styles.muted),
              ),
            )
          else
            Column(
              key: ValueKey('checkin-past-list-$id'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.checkIns.length; i++) ...[
                  if (i > 0) const ExperimentHairline(),
                  _Entry(checkIn: widget.checkIns[i]),
                ],
              ],
            ),
      ],
    );
  }
}

/// One entry: a fixed 64 wide date column and the note beside it.
class _Entry extends StatelessWidget {
  const _Entry({required this.checkIn});

  final ExperimentCheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final date = parseIsoDate(checkIn.slotDate);
    return Padding(
      key: ValueKey('checkin-item-${checkIn.slotDate}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM d').format(date),
                  style: styles.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: styles.muted,
                  ),
                ),
                Text(DateFormat('EEE').format(date), style: styles.caption),
              ],
            ),
          ),
          Expanded(
            child: SelectableText(
              checkIn.note,
              style: styles.body.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
