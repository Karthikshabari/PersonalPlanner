import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

/// execute: soft-delete (deleted_at = now); undo: restore the task from the
/// snapshot taken before deletion.
class DeleteTaskCommand implements SchedulingCommand {
  final TaskRepository repository;

  /// Immutable snapshot of the task before deletion.
  final Task original;

  DeleteTaskCommand({
    required this.repository,
    required this.original,
  });

  @override
  String get description => 'Delete "${original.title}"';

  @override
  Future<void> execute() async {
    await repository.deleteTask(original.id);
  }

  @override
  Future<void> undo() async {
    final current = await repository.getTaskById(original.id);
    if (current == null) {
      // Row was hard-deleted externally — recreate from the snapshot.
      final restored = await repository.insertTask(original);
      assert(restored.id == original.id);
      return;
    }
    await repository.updateTask(original.copyWith(deletedAt: null));
  }
}
