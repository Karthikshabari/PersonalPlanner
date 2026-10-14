import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/experiment.dart';
import '../../../core/models/inbox_closure.dart';
import '../../../core/models/inbox_item.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/json_map_utils.dart';
import '../../../core/utils/uuid.dart';
import '../../../core/utils/date_utils.dart';
import '../../timeline/data/task_repository.dart';
import '../domain/inbox_dates.dart';
import '../domain/inbox_history.dart';
import '../domain/inbox_session_text.dart';
import '../domain/inbox_source.dart';
import '../domain/inbox_status.dart';

/// Inbox data access per architecture.md §3 "Inbox representation" and the
/// Inbox Overdue Surfacing data flow.
class InboxRepository {
  final AppDatabase _db;

  InboxRepository(this._db);

  TaskRepository get _tasks => TaskRepository(_db);

  AppDatabase get database => _db;

  /// Stream of everything the inbox shows:
  /// - explicit inbox items (`is_inbox = 1`, unscheduled)
  /// - overdue tasks (`DATE(start_time) < today`, still planned/in-progress,
  ///   scheduled rows) surfaced query-side without moving them.
  Stream<List<InboxItem>> watchInboxItems([DateTime? asOf]) {
    final effectiveNow = asOf ?? DateTime.now();
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            ((t.isInbox.equals(true) &
                    t.startTime.isNull() &
                    t.status.isNotIn([
                      TaskStatus.completed.dbValue,
                      TaskStatus.cancelled.dbValue,
                      TaskStatus.skipped.dbValue,
                    ])) |
                (t.isInbox.equals(false) &
                    t.endTime.isNotNull() &
                    t.endTime.isSmallerThanValue(_utcIso(effectiveNow)) &
                    t.status.isIn([
                      TaskStatus.planned.dbValue,
                      TaskStatus.inProgress.dbValue,
                    ]))),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startTime)]);

    return query.watch().map((rows) {
      final items = <InboxItem>[];
      for (final row in rows) {
        final task = TaskRepository.fromRow(row);
        if (task.isInbox && task.startTime == null) {
          // A closed idea is history, not a decision for Day's panel.
          if (InboxHistory.isClosed(task.inboxHistory)) continue;
          items.add(InboxItem.explicit(task));
        } else if (!task.isInbox &&
            task.startTime != null &&
            task.endTime != null &&
            task.endTime!.isBefore(effectiveNow) &&
            (task.status == TaskStatus.planned ||
                task.status == TaskStatus.inProgress)) {
          items.add(InboxItem.overdue(task));
        }
      }
      // Explicit inbox first, then overdue by original date.
      items.sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? 1 : -1;
        if (a.isOverdue) {
          return a.task.startTime!.compareTo(b.task.startTime!);
        }
        return a.task.createdAt.compareTo(b.task.createdAt);
      });
      return items;
    });
  }

  Future<Task> addToInbox(String content, {String? dueDate}) {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }
    if (dueDate != null && !isValidIsoDate(dueDate)) {
      throw ArgumentError.value(
        dueDate,
        'dueDate',
        'must be a valid yyyy-MM-dd date',
      );
    }
    final now = DateTime.now();
    return _tasks.insertTask(
      Task(
        id: '',
        // The title is an internal compatibility value. The raw capture is
        // authoritative in description and is never trimmed or truncated.
        title: 'Inbox capture',
        description: content,
        isInbox: true,
        inboxContentVersion: 1,
        dueDate: dueDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Overdue stamping: any scheduled task whose end time has passed while
  /// still planned/in-progress gets `missed_at` set once, to the UTC minute of
  /// its planned end. Format: `YYYY-MM-DDTHH:mm` (UTC), per architecture.md §3.
  Future<int> stampOverdue([DateTime? asOf]) async {
    final now = (asOf ?? DateTime.now()).toUtc();
    // The minute the task became overdue is a pure function of its planned
    // end, so every device stamps the same value and concurrent stamps
    // converge instead of conflicting.
    // `customUpdate` reports its tables as changed even when no row matched,
    // which re-queries every task stream once a minute; report only a stamp
    // that changed rows.
    final stamped = await _db.customUpdate(
      "UPDATE tasks SET missed_at = strftime('%Y-%m-%dT%H:%M', end_time), "
      'updated_at = ?, sync_status = 1, revision = revision + 1 '
      'WHERE deleted_at IS NULL AND is_inbox = 0 AND missed_at IS NULL '
      "AND end_time IS NOT NULL AND end_time < ? AND status IN ('planned', 'in_progress')",
      variables: [
        Variable<String>(now.toIso8601String()),
        Variable<String>(_utcIso(now)),
      ],
    );
    if (stamped > 0) {
      _db.notifyUpdates({
        TableUpdate.onTable(_db.tasks, kind: UpdateKind.update),
      });
    }
    return stamped;
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  /// Everything the Inbox board is derived from, in one read transaction with
  /// four light queries (no typed full-row mapping).
  Future<InboxSource> readSource() {
    return _db.transaction(() async {
      final ideaRows = await _db
          .customSelect(
            'SELECT id, description, created_at, due_date, inbox_history_json '
            'FROM tasks WHERE is_inbox = 1 AND deleted_at IS NULL '
            "AND status IN ('planned', 'in_progress')",
            readsFrom: {_db.tasks},
          )
          .get();
      final items = <InboxItemFacts>[];
      final experimentIds = <String>{};
      for (final row in ideaRows) {
        var history = const <InboxClosure>[];
        try {
          history = InboxHistory.decodeJson(
            row.read<String>('inbox_history_json'),
          );
        } on FormatException {
          // Sync and backup validate the history; a bad value here is shown
          // as an idea with no history rather than breaking the whole list.
        }
        for (final event in history) {
          final id = event.experimentId;
          if (id != null) experimentIds.add(id);
        }
        items.add(
          InboxItemFacts(
            id: row.read<String>('id'),
            text: row.readNullable<String>('description') ?? '',
            createdAt: _parseInstant(row.read<String>('created_at'))!,
            dueDate: row.readNullable<String>('due_date'),
            history: history,
          ),
        );
      }

      final sessionRows = await _db
          .customSelect(
            'SELECT id, inbox_item_id, title, start_time, end_time, status, '
            'deleted_at, created_at FROM tasks WHERE inbox_item_id IS NOT NULL',
            readsFrom: {_db.tasks},
          )
          .get();
      final sessions = <InboxSessionFacts>[];
      final datesToRead = <String>{};
      final sessionDates = <String, String>{};
      for (final row in sessionRows) {
        final start = _parseInstant(row.readNullable<String>('start_time'));
        final status = TaskStatus.fromDb(row.read<String>('status'));
        final deletedAt = _parseInstant(row.readNullable<String>('deleted_at'));
        final id = row.read<String>('id');
        sessions.add(
          InboxSessionFacts(
            id: id,
            itemId: row.read<String>('inbox_item_id'),
            title: row.read<String>('title'),
            start: start,
            end: _parseInstant(row.readNullable<String>('end_time')),
            status: status,
            deletedAt: deletedAt,
            createdAt: _parseInstant(row.read<String>('created_at'))!,
          ),
        );
        // A reason can only exist for a session that is not done.
        if (deletedAt == null &&
            start != null &&
            status != TaskStatus.completed) {
          final date = isoDateString(start);
          datesToRead.add(date);
          sessionDates[id] = date;
        }
      }

      final reasons = <String, String>{};
      if (datesToRead.isNotEmpty) {
        final dates = datesToRead.toList(growable: false);
        final reviewRows = await _db
            .customSelect(
              'SELECT date, task_reasons_json FROM daily_reviews '
              'WHERE deleted_at IS NULL AND date IN '
              '(${List.filled(dates.length, '?').join(', ')})',
              variables: [for (final date in dates) Variable<String>(date)],
              readsFrom: {_db.dailyReviews},
            )
            .get();
        final byDate = {
          for (final row in reviewRows)
            row.read<String>('date'): JsonMapUtils.decode(
              row.readNullable<String>('task_reasons_json'),
            ),
        };
        sessionDates.forEach((id, date) {
          final reason = byDate[date]?[id]?.trim();
          if (reason != null && reason.isNotEmpty) reasons[id] = reason;
        });
      }

      final experiments = <String, InboxExperimentFacts>{};
      if (experimentIds.isNotEmpty) {
        final ids = experimentIds.toList(growable: false);
        final rows = await _db
            .customSelect(
              'SELECT e.id, e.start_date, e.end_date, e.status, e.outcome, '
              'e.concluded_on, e.retired_at, e.deleted_at, t.name '
              'FROM experiments e JOIN tags t ON t.id = e.tag_id '
              'WHERE e.id IN (${List.filled(ids.length, '?').join(', ')})',
              variables: [for (final id in ids) Variable<String>(id)],
              readsFrom: {_db.experiments, _db.tags},
            )
            .get();
        for (final row in rows) {
          final id = row.read<String>('id');
          experiments[id] = InboxExperimentFacts(
            id: id,
            name: row.read<String>('name'),
            startDate: row.read<String>('start_date'),
            endDate: row.read<String>('end_date'),
            status: ExperimentStatus.fromDb(row.read<String>('status')),
            outcome: ExperimentOutcome.fromDb(
              row.readNullable<String>('outcome'),
            ),
            concludedOn: row.readNullable<String>('concluded_on'),
            retiredAt: _parseInstant(row.readNullable<String>('retired_at')),
            deletedAt: _parseInstant(row.readNullable<String>('deleted_at')),
          );
        }
      }

      return InboxSource(
        items: items,
        sessions: sessions,
        reasons: reasons,
        experiments: experiments,
      );
    });
  }

  // ---------------------------------------------------------------------
  // Writes. Every one is a single write transaction; task writes go through
  // TaskRepository (validation, timers, stats invalidation, triggers). `now`
  // is always passed in.
  // ---------------------------------------------------------------------

  /// Plans one session of an idea on Day (the drag path). The idea row is not
  /// converted; it stays an idea and its legacy due date is cleared.
  Future<Task> createSession(
    String itemId,
    DateTime start,
    DateTime end, {
    required DateTime now,
    String? title,
    String? description,
    String? sessionId,
  }) {
    return _db.writeTransaction(() async {
      final idea = await _requireOpenIdea(itemId);
      final text = inboxSessionText(idea.$1.description ?? '');
      final desiredTitle = title ?? text.title;
      final desiredDescription = description == null
          ? text.description
          : (description.trim().isEmpty ? null : description);
      final id = sessionId ?? generateUuidV7();
      final existing = await _tasks.getTaskById(id);
      if (existing != null) {
        final sameRequest =
            existing.deletedAt == null &&
            existing.inboxItemId == itemId &&
            existing.title == desiredTitle &&
            existing.description == desiredDescription &&
            existing.startTime == start &&
            existing.endTime == end;
        if (sameRequest) return existing;
        throw StateError(
          'This session id already exists with different values.',
        );
      }
      final session = await _tasks.insertTask(
        Task(
          id: id,
          title: desiredTitle.isEmpty ? 'Inbox idea' : desiredTitle,
          description: desiredDescription,
          startTime: start,
          endTime: end,
          inboxItemId: itemId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _clearLegacyDueDate(idea);
      return session;
    });
  }

  /// Replaces the idea's upcoming sessions with [slots] and decides its
  /// missed ones (plan section 9.A). Everything in one transaction.
  Future<InboxSaveSummary> saveDates(
    String itemId,
    List<InboxSlot> slots,
    DateTime now,
  ) {
    return _db.writeTransaction(() async {
      // 1. The idea must be open.
      final idea = await _requireOpenIdea(itemId);
      // 2. Every slot is valid; at most 14, one per date.
      validateInboxSlots(slots, now);
      final ordered = [...slots]..sort((a, b) => a.start.compareTo(b.start));

      final rows = await _sessionsOf(itemId);
      final byId = {for (final row in rows) row.$1.id: row};
      final facts = [for (final row in rows) _factsOf(row.$1)];
      // 3. Replaceable sessions; the rest are never touched.
      final replaceable = replaceableInboxSessions(facts, now);
      final replaceableByDate = <String, List<InboxSessionFacts>>{};
      for (final session in replaceable) {
        (replaceableByDate[isoDateString(session.start!)] ??= []).add(session);
      }

      var created = 0;
      var moved = 0;
      var dropped = 0;
      final text = inboxSessionText(idea.$1.description ?? '');
      final sessionForDate = <String, String>{};

      // 4. One session per picked date: move the existing one or insert.
      for (final slot in ordered) {
        final existing = replaceableByDate[slot.date];
        if (existing != null && existing.isNotEmpty) {
          final keep = existing.first;
          sessionForDate[slot.date] = keep.id;
          final (task, revision) = byId[keep.id]!;
          if (!task.startTime!.isAtSameMomentAs(slot.start) ||
              !task.endTime!.isAtSameMomentAs(slot.end)) {
            await _tasks.updateTask(
              task.copyWith(startTime: slot.start, endTime: slot.end),
              expectedRevision: revision,
            );
            moved++;
          }
          for (final extra in existing.skip(1)) {
            await _tasks.deleteTask(extra.id);
            dropped++;
          }
        } else {
          final session = await _tasks.insertTask(
            Task(
              id: generateUuidV7(),
              title: text.title.isEmpty ? 'Inbox idea' : text.title,
              description: text.description,
              startTime: slot.start,
              endTime: slot.end,
              inboxItemId: itemId,
              createdAt: now,
              updatedAt: now,
            ),
          );
          sessionForDate[slot.date] = session.id;
          created++;
        }
      }

      // 5. Replaceable sessions on dates that were not picked are dropped.
      for (final entry in replaceableByDate.entries) {
        if (sessionForDate.containsKey(entry.key)) continue;
        for (final session in entry.value) {
          await _tasks.deleteTask(session.id);
          dropped++;
        }
      }

      // 6. Missed sessions: carried when any slot exists, else skipped.
      final missed = [
        for (final session in facts)
          if (sessionStatusOf(session, now) == InboxSessionStatus.missed)
            session,
      ]..sort((a, b) => a.start!.compareTo(b.start!));
      var carried = 0;
      var skipped = 0;
      if (missed.isNotEmpty) {
        if (ordered.isNotEmpty) {
          final targetId = sessionForDate[ordered.first.date]!;
          for (final session in missed) {
            await _tasks.markRescheduled(session.id, targetId);
            carried++;
          }
          final target = await _tasks.getTaskById(targetId);
          if (target != null && target.rescheduledFromId == null) {
            await _tasks.updateTask(
              target.copyWith(rescheduledFromId: missed.last.id),
            );
          }
        } else {
          for (final session in missed) {
            final (task, revision) = byId[session.id]!;
            await _tasks.updateTask(
              task.copyWith(status: TaskStatus.skipped),
              expectedRevision: revision,
            );
            skipped++;
          }
        }
      }

      // 7. The legacy due date has done its job.
      await _clearLegacyDueDate(idea);

      return InboxSaveSummary(
        created: created,
        moved: moved,
        dropped: dropped,
        carried: carried,
        skipped: skipped,
      );
    });
  }

  /// Closes an idea with a required reason (trimmed, at most 200 characters).
  Future<void> closeItem(String itemId, String reason, DateTime now) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Write why you are closing this idea.');
    }
    if (trimmed.runes.length > InboxHistory.maxReasonLength) {
      throw ArgumentError('Keep the reason to 200 characters or fewer.');
    }
    return await _closeIdea(
      itemId,
      now,
      kind: InboxCloseKind.closed,
      reason: trimmed,
    );
  }

  /// Lets an idea go, with an optional reason. Refused while the idea has any
  /// session that is not dropped; close it instead.
  Future<void> letGo(String itemId, String? reason, DateTime now) async {
    final trimmed = reason?.trim();
    if (trimmed != null &&
        trimmed.runes.length > InboxHistory.maxReasonLength) {
      throw ArgumentError('Keep the reason to 200 characters or fewer.');
    }
    return await _closeIdea(
      itemId,
      now,
      kind: InboxCloseKind.letGo,
      reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }

  /// Records that the idea became experiment [experimentId]. Called from the
  /// experiment start form inside the transaction that creates the experiment.
  Future<void> markBecameExperiment(
    String itemId,
    String experimentId,
    DateTime now,
  ) async {
    if (experimentId.trim().isEmpty) {
      throw ArgumentError('An experiment id is required.');
    }
    return await _closeIdea(
      itemId,
      now,
      kind: InboxCloseKind.experiment,
      experimentId: experimentId,
    );
  }

  /// Reverses the open closure. The event stays in the history with its
  /// reason; sessions are untouched, so the idea lands in Ideas.
  Future<void> bringBack(String itemId, DateTime now) {
    return _db.writeTransaction(() async {
      final idea = await _requireIdea(itemId);
      if (!InboxHistory.isClosed(idea.$1.inboxHistory)) {
        throw StateError('This idea is not closed.');
      }
      await _tasks.updateTask(
        idea.$1.copyWith(
          inboxHistory: InboxHistory.reopen(idea.$1.inboxHistory, now),
        ),
        expectedRevision: idea.$2,
      );
    });
  }

  Future<void> _closeIdea(
    String itemId,
    DateTime now, {
    required InboxCloseKind kind,
    String? reason,
    String? experimentId,
  }) {
    return _db.writeTransaction(() async {
      final idea = await _requireOpenIdea(itemId);
      final rows = await _sessionsOf(itemId);
      final facts = [for (final row in rows) _factsOf(row.$1)];
      if (kind == InboxCloseKind.letGo &&
          facts.any(
            (session) =>
                sessionStatusOf(session, now) != InboxSessionStatus.dropped,
          )) {
        throw StateError(
          'This idea has sessions. Close it instead of letting it go.',
        );
      }
      final history = InboxHistory.close(
        idea.$1.inboxHistory,
        kind: kind,
        at: now,
        reason: reason,
        experimentId: experimentId,
      );
      await _tasks.updateTask(
        idea.$1.copyWith(inboxHistory: history),
        expectedRevision: idea.$2,
      );
      // Sessions that have not started are dropped; missed ones are skipped
      // so Day stops asking about them; one in progress is left to Day.
      for (final (task, revision) in rows) {
        if (task.deletedAt != null ||
            (task.status != TaskStatus.planned &&
                task.status != TaskStatus.inProgress) ||
            task.startTime == null ||
            task.endTime == null) {
          continue;
        }
        if (task.startTime!.isAfter(now)) {
          await _tasks.deleteTask(task.id);
        } else if (!task.endTime!.isAfter(now)) {
          await _tasks.updateTask(
            task.copyWith(status: TaskStatus.skipped),
            expectedRevision: revision,
          );
        }
      }
    });
  }

  /// The idea row and its revision; throws unless it is a live Inbox idea.
  Future<(Task, int)> _requireIdea(String itemId) async {
    final snapshot = await _tasks.getTaskWithRevision(itemId);
    final task = snapshot?.$1;
    if (task == null || !task.isInbox || task.deletedAt != null) {
      throw StateError(_ideaChanged);
    }
    return snapshot!;
  }

  /// Like [_requireIdea], and the idea must not be closed.
  Future<(Task, int)> _requireOpenIdea(String itemId) async {
    final idea = await _requireIdea(itemId);
    if (InboxHistory.isClosed(idea.$1.inboxHistory)) {
      throw StateError(_ideaChanged);
    }
    return idea;
  }

  static const _ideaChanged =
      'This idea changed elsewhere. Close it and open it again.';

  Future<Task?> _liveIdea(String itemId) async {
    final task = await _tasks.getTaskById(itemId);
    return task != null && task.isInbox && task.deletedAt == null ? task : null;
  }

  Future<void> _clearLegacyDueDate((Task, int) idea) async {
    if (idea.$1.dueDate == null) return;
    await _tasks.updateTask(
      idea.$1.copyWith(dueDate: null),
      expectedRevision: idea.$2,
    );
  }

  /// Every row linked to [itemId] (deleted ones too) with its revision.
  Future<List<(Task, int)>> _sessionsOf(String itemId) async {
    final rows = await (_db.select(
      _db.tasks,
    )..where((t) => t.inboxItemId.equals(itemId))).get();
    return [
      for (final row in rows) (TaskRepository.fromRow(row), row.revision),
    ];
  }

  static InboxSessionFacts _factsOf(Task task) => InboxSessionFacts(
    id: task.id,
    itemId: task.inboxItemId!,
    title: task.title,
    start: task.startTime?.toUtc(),
    end: task.endTime?.toUtc(),
    status: task.status,
    deletedAt: task.deletedAt?.toUtc(),
    createdAt: task.createdAt.toUtc(),
  );

  static DateTime? _parseInstant(String? value) =>
      value == null ? null : DateTime.parse(value).toUtc();

  /// Marks an inbox/overdue item as skipped without scheduling it
  /// (Flow 6 "Mark as Skipped").
  Future<Task> scheduleStatus(String taskId, TaskStatus status) async {
    final task = await _tasks.getTaskById(taskId);
    if (task == null) throw StateError('Task $taskId not found');
    return _tasks.updateTask(task.copyWith(status: status));
  }

  /// Reschedules an overdue task (Flow 6): the original row becomes
  /// `rescheduled` and links to a newly created task at the drop position.
  Future<Task> rescheduleOverdue(
    String originalId,
    DateTime newStart,
    DateTime newEnd, {
    String? successorId,
    String? title,
    String? description,
    bool replaceDescription = false,
  }) {
    return _db.transaction(() async {
      final original = await _tasks.getTaskById(originalId);
      if (original == null || original.deletedAt != null) {
        throw StateError('Task $originalId not found');
      }
      if (original.status != TaskStatus.planned &&
          original.status != TaskStatus.inProgress) {
        throw StateError('Only unfinished tasks can be rescheduled');
      }

      final now = DateTime.now();
      // A carried session stays linked to its idea; a link to an idea that
      // is gone would be refused, so the successor is then a plain Day task.
      final itemId = original.inboxItemId;
      final keepLink = itemId != null && await _liveIdea(itemId) != null;
      final newTask = await _tasks.insertTask(
        original.copyWith(
          id: successorId ?? generateUuidV7(),
          inboxItemId: keepLink ? itemId : null,
          title: title ?? original.title,
          description: replaceDescription ? description : original.description,
          isInbox: false,
          startTime: newStart,
          endTime: newEnd,
          actualDurationMin: null,
          manualDurationAdjustmentMin: 0,
          manualActualSet: false,
          planTitleHistory: const [],
          planChangeReasons: const {},
          displayPlanChangeId: null,
          status: TaskStatus.planned,
          recurringRuleId: original.recurringRuleId,
          rescheduledFromId: original.id,
          rescheduledToId: null,
          missedAt: null,
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
        ),
      );

      final links =
          await (_db.select(_db.taskTags)..where(
                (row) =>
                    row.taskId.equals(original.id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final link in links) {
        await _db.tagDao.linkTaskTag(newTask.id, link.tagId, now);
      }

      final unfinished =
          await (_db.select(_db.subtasks)
                ..where(
                  (row) =>
                      row.taskId.equals(original.id) &
                      row.deletedAt.isNull() &
                      row.isCompleted.equals(false),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
              .get();
      for (var index = 0; index < unfinished.length; index++) {
        await _db
            .into(_db.subtasks)
            .insert(
              SubtasksCompanion.insert(
                id: generateUuidV7(),
                taskId: newTask.id,
                title: unfinished[index].title,
                isCompleted: const Value(false),
                sortOrder: Value(index),
                createdAt: now,
                updatedAt: now,
                syncStatus: const Value(1),
                revision: const Value(1),
              ),
            );
      }

      await _tasks.markRescheduled(original.id, newTask.id);
      return newTask;
    });
  }

  static String _utcIso(DateTime local) => local.toUtc().toIso8601String();
}

/// What Save dates did, for the confirmation line and tests.
class InboxSaveSummary {
  const InboxSaveSummary({
    this.created = 0,
    this.moved = 0,
    this.dropped = 0,
    this.carried = 0,
    this.skipped = 0,
  });

  final int created;
  final int moved;
  final int dropped;
  final int carried;
  final int skipped;

  @override
  bool operator ==(Object other) =>
      other is InboxSaveSummary &&
      other.created == created &&
      other.moved == moved &&
      other.dropped == dropped &&
      other.carried == carried &&
      other.skipped == skipped;

  @override
  int get hashCode => Object.hash(created, moved, dropped, carried, skipped);

  @override
  String toString() =>
      'InboxSaveSummary(created: $created, moved: $moved, dropped: $dropped, '
      'carried: $carried, skipped: $skipped)';
}
