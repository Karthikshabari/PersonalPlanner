import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';
import 'task_aggregate_snapshot.dart';

/// execute: soft-delete (deleted_at = now); undo: restore the task from the
/// snapshot taken before deletion.
class DeleteTaskCommand implements SchedulingCommand {
  final TaskRepository repository;

  /// Immutable snapshot of the task before deletion.
  final Task original;
  TaskAggregateSnapshot? _snapshot;

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
    await _snapshot?.softDelete(repository.database);
  }

  @override
  Future<void> undo() async {
    final snapshot = _snapshot;
    if (snapshot != null) await snapshot.restore(repository.database);
  }
}
