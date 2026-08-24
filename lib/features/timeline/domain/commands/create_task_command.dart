import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

/// execute: INSERT the task; undo: hard-delete it (so redo can re-insert
/// with the same deterministic UUIDv7 id).
class CreateTaskCommand implements SchedulingCommand {
  final TaskRepository repository;
  final Task _task;
  Task? _created;

  CreateTaskCommand(this.repository, this._task);

  @override
  String get description => 'Create "${_task.title}"';

  @override
  Future<void> execute() async {
    _created = await repository.insertTask(_task);
  }

  @override
  Future<void> undo() async {
    final created = _created;
    if (created == null) return;
    await repository.hardDeleteTask(created.id);
    _created = null;
  }
}
