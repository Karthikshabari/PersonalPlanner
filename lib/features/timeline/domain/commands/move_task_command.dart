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

  Future<void> _apply(
    DateTime start,
    DateTime end, {
    required DateTime? expectedStart,
    required DateTime? expectedEnd,
  }) async {
    final snapshot = await repository.getTaskWithRevision(original.id);
    final current = snapshot?.$1;
    final revision = snapshot?.$2;
    if (current == null || revision == null) return;
    if (current.startTime != expectedStart || current.endTime != expectedEnd) {
      throw StateError(
        'Task ${original.id} changed while the schedule operation was pending; reload and try again.',
      );
    }
    await repository.updateTask(
      current.copyWith(startTime: start, endTime: end),
      expectedRevision: revision,
    );
  }

  @override
  Future<void> execute() => _apply(
    newStart,
    newEnd,
    expectedStart: original.startTime,
    expectedEnd: original.endTime,
  );

  @override
  Future<void> undo() => _apply(
    original.startTime!,
    original.endTime!,
    expectedStart: newStart,
    expectedEnd: newEnd,
  );
}
