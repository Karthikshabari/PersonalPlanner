import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

/// execute: UPDATE start/end to the new values; undo: UPDATE back to the
/// snapshot's original start/end.
class MoveTaskCommand implements SchedulingCommand {
  final TaskRepository repository;

  /// Immutable snapshot of the task before the move.
  final Task original;
  final DateTime newStart;
  final DateTime newEnd;

  MoveTaskCommand({
    required this.repository,
    required this.original,
    required this.newStart,
    required this.newEnd,
  });

  @override
  String get description => 'Move "${original.title}"';

  Future<void> _apply(DateTime start, DateTime end) async {
    final current = await repository.getTaskById(original.id);
    if (current == null) return;
    await repository.updateTask(
      current.copyWith(startTime: start, endTime: end),
    );
  }

  @override
  Future<void> execute() => _apply(newStart, newEnd);

  @override
  Future<void> undo() => _apply(original.startTime!, original.endTime!);
}
