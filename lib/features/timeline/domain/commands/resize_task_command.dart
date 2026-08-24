import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

/// execute: UPDATE end_time to the new value; undo: restore the old end_time.
class ResizeTaskCommand implements SchedulingCommand {
  final TaskRepository repository;

  /// Immutable snapshot of the task before the resize.
  final Task original;
  final DateTime newEnd;

  ResizeTaskCommand({
    required this.repository,
    required this.original,
    required this.newEnd,
  });

  @override
  String get description => 'Resize "${original.title}"';

  Future<void> _apply(DateTime? end) async {
    final current = await repository.getTaskById(original.id);
    if (current == null) return;
    await repository.updateTask(current.copyWith(endTime: end));
  }

  @override
  Future<void> execute() => _apply(newEnd);

  @override
  Future<void> undo() => _apply(original.endTime);
}
