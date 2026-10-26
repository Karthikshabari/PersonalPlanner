import '../../../core/models/task.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/utils/uuid.dart';
import '../../timeline/data/task_repository.dart';
import '../../timeline/domain/commands/scheduling_command.dart';
import '../../timeline/domain/commands/task_aggregate_snapshot.dart';
import '../data/inbox_repository.dart';

/// Plans one session of an Inbox idea on Day (drag and drop, or the tile's
/// Schedule). The idea row is not converted: a new Day task linked to it by
/// `inbox_item_id` is created, with an id generated up front so Undo and Redo
/// refer to the same row. Undo soft-deletes only that session, and only while
/// it is as this command left it.
class ScheduleInboxItemCommand
    implements SchedulingCommand, MutationAwareSchedulingCommand {
  final InboxRepository repository;

  /// The idea's id.
  final String itemId;
  final DateTime start;
  final DateTime end;
  final String? title;
  final String? descriptionText;

  /// The session this command creates.
  final String sessionId = generateUuidV7();

  TaskAggregateSnapshot? _snapshot;
  Task? _created;
  String? _dueDateBefore;
  bool _didMutate = true;

  ScheduleInboxItemCommand({
    required this.repository,
    required this.itemId,
    required this.start,
    required this.end,
    this.title,
    String? description,
  }) : descriptionText = description;

  @override
  String get description => 'Schedule inbox item';

  @override
  bool get didMutate => _didMutate;

  @override
  Future<void> execute() async {
    final tasks = TaskRepository(repository.database);
    final snapshot = _snapshot;
    if (snapshot != null) {
      // Redo: bring the same session back and clear the legacy due date again.
      await repository.database.writeTransaction(() async {
        await snapshot.restore(repository.database);
        await _setIdeaDueDate(tasks, null, onlyIf: _dueDateBefore);
      });
      return;
    }
    final idea = await tasks.getTaskById(itemId);
    _dueDateBefore = idea?.dueDate;
    final session = await repository.createSession(
      itemId,
      start,
      end,
      now: DateTime.now(),
      title: title,
      description: descriptionText,
      sessionId: sessionId,
    );
    // Read back, so the guarded Undo compares with what is stored.
    _created = await tasks.getTaskById(session.id) ?? session;
    _didMutate = true;
    _snapshot = await TaskAggregateSnapshot.capture(
      repository.database,
      sessionId,
    );
  }

  @override
  Future<void> undo() async {
    final created = _created;
    final snapshot = _snapshot;
    if (created == null || snapshot == null || !_didMutate) return;
    final tasks = TaskRepository(repository.database);
    await repository.database.writeTransaction(() async {
      final current = await tasks.getTaskById(sessionId);
      if (current == null || current.deletedAt != null) {
        throw StateError(
          'Cannot undo scheduling: the task is no longer available.',
        );
      }
      if (current.status != TaskStatus.planned &&
          current.status != TaskStatus.inProgress) {
        throw StateError(
          'Undo the later task status change before undoing this scheduling change.',
        );
      }
      if (await repository.database.timerDao.getActiveTimerForTask(sessionId) !=
          null) {
        throw StateError(
          'Stop the active timer before undoing this scheduling change.',
        );
      }
      if (!_sameOwnedFields(current, created)) {
        throw StateError(
          'Cannot undo scheduling because the task changed after it was scheduled.',
        );
      }
      await snapshot.softDelete(repository.database);
      // Put back the legacy due date this command cleared, unless the user
      // has set another one since.
      await _setIdeaDueDate(tasks, _dueDateBefore, onlyIf: null);
    });
  }

  /// Sets the idea's due date to [value] when its current value is [onlyIf]
  /// and the idea is still a live Inbox idea.
  Future<void> _setIdeaDueDate(
    TaskRepository tasks,
    String? value, {
    required String? onlyIf,
  }) async {
    if (value == onlyIf) return;
    final snapshot = await tasks.getTaskWithRevision(itemId);
    final idea = snapshot?.$1;
    if (idea == null ||
        !idea.isInbox ||
        idea.deletedAt != null ||
        idea.dueDate != onlyIf) {
      return;
    }
    await tasks.updateTask(
      idea.copyWith(dueDate: value),
      expectedRevision: snapshot!.$2,
    );
  }

  bool _sameOwnedFields(Task left, Task right) =>
      left.title == right.title &&
      left.description == right.description &&
      _sameInstant(left.startTime, right.startTime) &&
      _sameInstant(left.endTime, right.endTime);

  static bool _sameInstant(DateTime? a, DateTime? b) =>
      a == null || b == null ? a == b : a.isAtSameMomentAs(b);
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
    final current = await TaskRepository(repository.database)
        .getTaskById(originalId);
    if (current != null && current.deletedAt == null) {
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
