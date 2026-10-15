import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../providers/experiment_providers.dart';

const experimentUndoDeleteFailed =
    "Couldn't undo. The experiment changed on another device.";

const experimentUndoEndFailed =
    "Couldn't undo. The experiment changed since it was ended.";

String experimentDeletedLine(String name) => 'Deleted $name.';

String experimentDeleteMessage(String name, int checkIns) =>
    '"$name" will be removed from Insights on all your devices. '
    '${checkIns == 0
        ? ''
        : checkIns == 1
        ? 'Its 1 check-in goes with it. '
        : 'Its $checkIns check-ins go with it. '}'
    'Your blocks keep the tag "$name" and their time.';

const experimentEndedLine = 'Ended today.';

String experimentEndTodayMessage(String name, String oldEnd, String today) {
  String monthDay(String iso) => DateFormat('MMM d').format(parseIsoDate(iso));
  return 'End "$name" today? Its end date moves from ${monthDay(oldEnd)} '
      'to ${monthDay(today)}. You can then keep it or drop it.';
}

enum _Action { delete, endToday }

/// The ⋮ button in the header of an experiment card. Delete experiment is
/// always there; End today only for a running experiment with
/// `startDate <= today < endDate`. [startDate] and [endDate] are null where
/// End today never applies (kept rows).
class ExperimentActionsMenu extends ConsumerWidget {
  const ExperimentActionsMenu({
    super.key,
    required this.experimentId,
    required this.name,
    required this.revision,
    this.startDate,
    this.endDate,
  });

  final String experimentId;
  final String name;
  final int revision;

  /// `yyyy-MM-dd`; set only for a running experiment.
  final String? startDate;
  final String? endDate;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(experimentRepositoryProvider);
    final deleted = ref.read(experimentDeletedProvider.notifier);
    try {
      final checkIns = await repository.countCheckIns(experimentId);
      if (!context.mounted) return;
      final confirmed = await showConfirmDialog(
        context,
        title: 'Delete experiment?',
        message: experimentDeleteMessage(name, checkIns),
      );
      if (!confirmed) return;
      final newRevision = await repository.deleteExperiment(
        experimentId,
        expectedRevision: revision,
      );
      deleted.state = (
        experimentId: experimentId,
        name: name,
        revision: newRevision,
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, 'That change was not saved. Try again.');
      }
    }
  }

  Future<void> _endToday(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(experimentRepositoryProvider);
    final ended = ref.read(experimentEndedProvider.notifier);
    final end = endDate;
    final today = isoDateString(ref.read(insightsNowProvider));
    if (end == null) return;
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: 'End today?',
        message: experimentEndTodayMessage(name, end, today),
        confirmLabel: 'End today',
        destructive: false,
      );
      if (!confirmed) return;
      final result = await repository.endExperimentToday(
        experimentId,
        today: today,
        expectedRevision: revision,
      );
      ended.state = (
        experimentId: experimentId,
        previousEndDate: result.previousEndDate,
        revision: result.revision,
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, 'That change was not saved. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_Action>(
      key: ValueKey('experiment-menu-$experimentId'),
      icon: const Icon(Icons.more_vert, size: 16),
      tooltip: 'More actions',
      onSelected: (action) {
        switch (action) {
          case _Action.delete:
            _delete(context, ref);
          case _Action.endToday:
            _endToday(context, ref);
        }
      },
      itemBuilder: (_) {
        final start = startDate;
        final end = endDate;
        final today = isoDateString(ref.read(insightsNowProvider));
        final canEndToday =
            start != null &&
            end != null &&
            start.compareTo(today) <= 0 &&
            today.compareTo(end) < 0;
        return [
          const PopupMenuItem(
            value: _Action.delete,
            child: Text('Delete experiment'),
          ),
          if (canEndToday)
            const PopupMenuItem(
              value: _Action.endToday,
              child: Text('End today'),
            ),
        ];
      },
    );
  }
}
