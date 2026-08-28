import '../../../core/models/task.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';
import '../../timeline/domain/commands/scheduling_command.dart';
import '../../timeline/domain/commands/task_aggregate_snapshot.dart';
import '../data/inbox_repository.dart';

class ScheduleInboxItemCommand implements SchedulingCommand {
  final InboxRepository repository;
  final String taskId;
  final DateTime start;
  final DateTime end;
  Task? _before;

  ScheduleInboxItemCommand({
    required this.repository,
    required this.taskId,
    required this.start,
    required this.end,
  });

  @override
  String get description => 'Schedule inbox item';

  @override
  Future<void> execute() async {
    _before ??= await TaskRepository(repository.database).getTaskById(taskId);
    await repository.scheduleItem(taskId, start, end);
  }

  @override
  Future<void> undo() async {
    final before = _before;
    if (before == null) return;
    await TaskRepository(repository.database).updateTask(before);
  }
}

class RescheduleOverdueCommand implements SchedulingCommand {
  final InboxRepository repository;
  final String originalId;
  final DateTime start;
  final DateTime end;

  final String successorId = generateUuidV7();
  Task? _originalBefore;
  TaskAggregateSnapshot? _successorSnapshot;

  RescheduleOverdueCommand({
    required this.repository,
    required this.originalId,
    required this.start,
    required this.end,
  });

  @override
  String get description => 'Reschedule overdue task';

  @override
  Future<void> execute() async {
    final tasks = TaskRepository(repository.database);
    _originalBefore ??= await tasks.getTaskById(originalId);
    final snapshot = _successorSnapshot;
    if (snapshot == null) {
      await repository.rescheduleOverdue(
        originalId,
        start,
        end,
        successorId: successorId,
      );
      _successorSnapshot = await TaskAggregateSnapshot.capture(
        repository.database,
        successorId,
      );
      return;
    }
    await snapshot.restore(repository.database);
    final original = await tasks.getTaskById(originalId);
    if (original == null) throw StateError('Task $originalId not found');
    await tasks.markRescheduled(originalId, successorId);
  }

  @override
  Future<void> undo() async {
    final before = _originalBefore;
    final snapshot = _successorSnapshot;
    if (before == null || snapshot == null) return;
    await snapshot.softDelete(repository.database);
    final current = await TaskRepository(repository.database).getTaskById(originalId);
    if (current != null) {
      await TaskRepository(repository.database).updateTask(current.copyWith(
        status: before.status,
        rescheduledToId: before.rescheduledToId,
      ));
    }
  }
}
