import '../../../core/models/task.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';
import '../../timeline/domain/commands/scheduling_command.dart';
import '../../timeline/domain/commands/task_aggregate_snapshot.dart';
import '../data/inbox_repository.dart';

/// Converts an explicit Inbox row into a scheduled task in place. Undo owns
/// only the fields changed by conversion, preserving later task metadata.
class ScheduleInboxItemCommand
    implements SchedulingCommand, MutationAwareSchedulingCommand {
  final InboxRepository repository;
  final String taskId;
  final DateTime start;
  final DateTime end;
  final String? title;
  final String? descriptionText;
  final bool replaceDescription;

  Task? _before;
  Task? _after;
  bool _didMutate = true;

  ScheduleInboxItemCommand({
    required this.repository,
    required this.taskId,
    required this.start,
    required this.end,
    this.title,
    String? description,
    this.replaceDescription = false,
  }) : descriptionText = description;

  @override
  String get description => 'Schedule inbox item';

  @override
  bool get didMutate => _didMutate;

  @override
  Future<void> execute() async {
    final tasks = TaskRepository(repository.database);
    final snapshot = await tasks.getTaskWithRevision(taskId);
    if (snapshot == null) throw StateError('Task $taskId not found');
    _before ??= snapshot.$1;
    final result = await repository.scheduleItemDetailed(
      taskId,
      start,
      end,
      title: title,
      description: descriptionText,
      replaceDescription: replaceDescription,
    );
    _after = result.after;
    _didMutate = result.changed;
  }

  @override
  Future<void> undo() async {
    final before = _before;
    final after = _after;
    if (before == null || after == null || !_didMutate) return;
    final tasks = TaskRepository(repository.database);
    await repository.database.transaction(() async {
      final snapshot = await tasks.getTaskWithRevision(taskId);
      final current = snapshot?.$1;
      final revision = snapshot?.$2;
      if (current == null || revision == null || current.deletedAt != null) {
        throw StateError('Cannot undo scheduling: the task is no longer available.');
      }
      if (current.status != TaskStatus.planned &&
          current.status != TaskStatus.inProgress) {
        throw StateError(
          'Undo the later task status change before undoing this scheduling change.',
        );
      }
      if (await repository.database.timerDao.getActiveTimerForTask(taskId) !=
          null) {
        throw StateError(
          'Stop the active timer before undoing this scheduling change.',
        );
      }
      if (!_sameOwnedFields(current, after)) {
        throw StateError(
          'Cannot undo scheduling because the task changed after it was scheduled.',
        );
      }
      await tasks.updateTask(
        current.copyWith(
          title: before.title,
          description: before.description,
          isInbox: before.isInbox,
          startTime: before.startTime,
          endTime: before.endTime,
          inboxContentVersion: before.inboxContentVersion,
        ),
        expectedRevision: revision,
        allowStatusTransition: true,
      );
    });
  }

  bool _sameOwnedFields(Task left, Task right) =>
      left.title == right.title &&
      left.description == right.description &&
      left.isInbox == right.isInbox &&
      left.startTime == right.startTime &&
      left.endTime == right.endTime &&
      left.inboxContentVersion == right.inboxContentVersion;
}

class RescheduleOverdueCommand implements SchedulingCommand {
  final InboxRepository repository;
  final String originalId;
  final DateTime start;
  final DateTime end;
  final String? title;
  final String? descriptionText;
  final bool replaceDescription;

  final String successorId = generateUuidV7();
  Task? _originalBefore;
  TaskAggregateSnapshot? _successorSnapshot;

  RescheduleOverdueCommand({
    required this.repository,
    required this.originalId,
    required this.start,
    required this.end,
    this.title,
    String? description,
    this.replaceDescription = false,
  }) : descriptionText = description;

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
        title: title,
        description: descriptionText,
        replaceDescription: replaceDescription,
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
    final current = await TaskRepository(repository.database).getTaskById(
      originalId,
    );
    if (current != null) {
      await TaskRepository(repository.database).updateTask(
        current.copyWith(
          status: before.status,
          rescheduledToId: before.rescheduledToId,
        ),
        allowStatusTransition: true,
      );
    }
  }
}
