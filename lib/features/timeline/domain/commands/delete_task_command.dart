import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';
import 'task_aggregate_snapshot.dart';

/// execute: soft-delete (deleted_at = now); undo: restore the task from the
/// snapshot taken before deletion. Blocks rescheduled to this task are healed
/// by the delete (Planned again) and linked to it again on Undo, so one task
/// never shows twice.
class DeleteTaskCommand implements SchedulingCommand {
  final TaskRepository repository;

  /// Immutable snapshot of the task before deletion.
  final Task original;
  TaskAggregateSnapshot? _snapshot;
  List<String> _healed = const <String>[];

  DeleteTaskCommand({
    required this.repository,
    required this.original,
  });

  @override
  String get description => 'Delete "${original.title}"';

  @override
  Future<void> execute() async {
    _snapshot ??= await TaskAggregateSnapshot.capture(
      repository.database,
      original.id,
    );
    _healed =
        await _snapshot?.softDelete(repository.database) ?? const <String>[];
  }

  @override
  Future<void> undo() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await snapshot.restore(repository.database);
    for (final id in _healed) {
      final healed = await repository.getTaskById(id);
      // Re-link only a block still as the delete left it; a later edit wins.
      if (healed != null &&
          healed.deletedAt == null &&
          healed.status == TaskStatus.planned &&
          healed.rescheduledToId == null) {
        await repository.markRescheduled(id, original.id);
      }
    }
  }
}
