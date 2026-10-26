import 'package:flutter/material.dart';

import '../../../../core/models/task.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../domain/timeline_geometry.dart';
import 'day_style.dart';

/// Compact, keyboard/touch accessible affordance for a dense overlap lane.
///
/// The underlying task block remains in the tree for its visual duration and
/// semantics. This action provides a reliable way to choose one task when
/// several blocks have too little horizontal space for independent hit
/// targets.
class TimelineOverlapAction extends StatelessWidget {
  final TimelineTaskGeometry geometry;
  final List<Task> tasks;
  final DateTime date;
  final ValueChanged<Task> onOpen;

  const TimelineOverlapAction({
    super.key,
    required this.geometry,
    required this.tasks,
    required this.date,
    required this.onOpen,
  });

  List<Task> get _componentTasks {
    final byId = {for (final task in tasks) task.id: task};
    final result = <Task>[];
    for (final id in geometry.componentTaskIds) {
      final task = byId[id];
      if (task != null) result.add(task);
    }
    return result;
  }

  String get _label => '${geometry.componentTaskIds.length} overlapping tasks';

  Future<void> _showComponent(BuildContext context) async {
    final componentTasks = _componentTasks;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_label),
        content: SizedBox(
          width: 460,
          height: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: componentTasks.length,
            itemBuilder: (context, index) {
              final task = componentTasks[index];
              return ListTile(
                title: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_timeRange(task)),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onOpen(task);
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _timeRange(Task task) {
    final start = task.startTime;
    final end = task.endTime;
    if (start == null || end == null) return 'Unscheduled';
    final localStart = PlannerTimeZone.toPlannerLocal(start);
    final localEnd = PlannerTimeZone.toPlannerLocal(end);
    String format(DateTime value) =>
        '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${format(localStart)} – ${format(localEnd)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = DayStyle.secondary(context);
    // A small corner chip, so the task title underneath stays readable.
    return Align(
      alignment: Alignment.topRight,
      child: Semantics(
        button: true,
        label: _label,
        hint: 'Show overlapping tasks',
        onTap: () => _showComponent(context),
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(DayStyle.small(context)),
          child: InkWell(
            key: ValueKey('timeline-overlap-action-${geometry.task.id}'),
            borderRadius: BorderRadius.circular(DayStyle.small(context)),
            onTap: () => _showComponent(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 12, color: style.color),
                  const SizedBox(width: 2),
                  Text(
                    '${geometry.componentTaskIds.length}',
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
