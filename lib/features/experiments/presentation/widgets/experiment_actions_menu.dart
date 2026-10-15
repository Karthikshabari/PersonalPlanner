import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../providers/experiment_providers.dart';

const experimentUndoDeleteFailed =
    "Couldn't undo. The experiment changed on another device.";

String experimentDeletedLine(String name) => 'Deleted $name.';

String experimentDeleteMessage(String name, int checkIns) =>
    '"$name" will be removed from Insights on all your devices. '
    '${checkIns == 0
        ? ''
        : checkIns == 1
        ? 'Its 1 check-in goes with it. '
        : 'Its $checkIns check-ins go with it. '}'
    'Your blocks keep the tag "$name" and their time.';

enum _Action { delete }

/// The ⋮ button in the header of an experiment card. It has one item, Delete
/// experiment; more items go into [_Action] and the menu below.
class ExperimentActionsMenu extends ConsumerWidget {
  const ExperimentActionsMenu({
    super.key,
    required this.experimentId,
    required this.name,
    required this.revision,
  });

  final String experimentId;
  final String name;
  final int revision;

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
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Action.delete, child: Text('Delete experiment')),
      ],
    );
  }
}
