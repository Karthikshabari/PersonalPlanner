import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/experiment_check_in.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';

/// The written check-ins of one experiment, newest slot first, behind a
/// "Show past check-ins (n)" toggle (ED31). There is no edit or delete
/// control: a check-in is never changed once it is written.
class ExperimentPastCheckIns extends StatefulWidget {
  const ExperimentPastCheckIns({
    super.key,
    required this.experimentId,
    required this.checkIns,
  });

  final String experimentId;

  /// Newest slot first.
  final List<ExperimentCheckIn> checkIns;

  @override
  State<ExperimentPastCheckIns> createState() => _ExperimentPastCheckInsState();
}

class _ExperimentPastCheckInsState extends State<ExperimentPastCheckIns> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.experimentId;
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final count = widget.checkIns.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: ValueKey('checkin-past-$id'),
          onPressed: () => setState(() => _open = !_open),
          child: Text(
            _open
                ? 'Hide past check-ins ($count)'
                : 'Show past check-ins ($count)',
          ),
        ),
        if (_open)
          if (widget.checkIns.isEmpty)
            Text(
              'No check-ins written yet.',
              key: ValueKey('checkin-past-empty-$id'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            )
          else
            Column(
              key: ValueKey('checkin-past-list-$id'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final checkIn in widget.checkIns)
                  Padding(
                    key: ValueKey('checkin-item-${checkIn.slotDate}'),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM d')
                              .format(parseIsoDate(checkIn.slotDate)),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(checkIn.note, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
      ],
    );
  }
}
