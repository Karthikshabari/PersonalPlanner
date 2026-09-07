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

  Future<void> _apply(
    DateTime? end, {
    required DateTime? expectedStart,
    required DateTime? expectedEnd,
  }) async {
    final snapshot = await repository.getTaskWithRevision(original.id);
    final current = snapshot?.$1;
    final revision = snapshot?.$2;
    if (current == null || revision == null) return;
    if (current.startTime != expectedStart || current.endTime != expectedEnd) {
      throw StateError(
        'Task ${original.id} changed while the resize operation was pending; reload and try again.',
      );
    }
    await repository.updateTask(
      current.copyWith(endTime: end),
      expectedRevision: revision,
    );
  }

  @override
  Future<void> execute() => _apply(
    newEnd,
    expectedStart: original.startTime,
    expectedEnd: original.endTime,
  );

  @override
  Future<void> undo() => _apply(
    original.endTime,
    expectedStart: original.startTime,
    expectedEnd: newEnd,
  );
}
