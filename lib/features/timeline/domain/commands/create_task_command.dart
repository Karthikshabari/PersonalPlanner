import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';
import 'task_aggregate_snapshot.dart';

/// Creation Undo is a reversible aggregate tombstone. Redo restores the same
/// task id and any subtasks/tags attached before Undo.
class CreateTaskCommand implements SchedulingCommand {
  final TaskRepository repository;
  final Task _task;
  Task? _created;
  TaskAggregateSnapshot? _snapshot;

  CreateTaskCommand(this.repository, this._task);

  @override
  String get description => 'Create "${_task.title}"';

  @override
  Future<void> execute() async {
    final snapshot = _snapshot;
    if (snapshot != null) {
      await snapshot.restore(repository.database);
      _created = TaskRepository.fromRow(snapshot.task);
      return;
    }
    _created = await repository.insertTask(_task);
  }

  @override
  Future<void> undo() async {
    final created = _created;
    if (created == null) return;
    _snapshot = await TaskAggregateSnapshot.capture(
      repository.database,
      created.id,
    );
    await _snapshot?.softDelete(repository.database);
  }
}
