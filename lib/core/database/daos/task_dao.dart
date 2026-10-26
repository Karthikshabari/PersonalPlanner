import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';
import '../../models/enums/task_status.dart';
import '../../models/plan_counting.dart';
import '../../utils/date_utils.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  /// Day tasks in chronological order — callers (timeline block layout,
  /// conflict planning) rely on start_time ordering.
  Stream<List<TaskRow>> watchTasksForDay(DateTime day) =>
      (select(tasks)
            ..where((t) {
              final (dayStart, dayEnd) = _dayBounds(day);
              return _dayFilter(t, dayStart, dayEnd: dayEnd);
            })
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .watch();

  /// One-shot variant of [watchTasksForDay] used by stats computation
  /// (planner.md Chunk 5 #9).
  Future<List<TaskRow>> getTasksForDay(DateTime day) =>
      (select(tasks)
            ..where((t) {
              final (dayStart, dayEnd) = _dayBounds(day);
              return _dayFilter(t, dayStart, dayEnd: dayEnd);
            })
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  /// Scheduled non-deleted tasks intersecting [start, end) — used for
  /// day/week-level aggregation.
  Future<List<TaskRow>> getTasksBetween(DateTime start, DateTime end) =>
      (select(tasks)
            ..where((t) => _dayFilter(t, start, dayEnd: end))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  /// The start instant and status of the same tasks [getTasksBetween] returns
  /// (the filter below mirrors [_dayFilter]; a test keeps them equal), without
  /// reading or decoding the other ~40 columns: 5 800 rows take about 13 ms
  /// this way against about 100 ms for the typed full-row query. For callers
  /// that only count tasks per day or week (Review Overview, Weekly history).
  /// Order is not specified. [successorLive] tells `plan_counting.dart`
  /// whether a rescheduled row's new block still exists.
  Future<
    List<
      ({
        DateTime start,
        String status,
        String? rescheduledToId,
        bool successorLive,
      })
    >
  >
  getStartAndStatusBetween(DateTime start, DateTime end) async {
    final rows = await customSelect(
      'SELECT t.start_time, t.status, t.rescheduled_to_id, $_successorLiveSql '
      'FROM tasks t WHERE t.deleted_at IS NULL '
      'AND t.is_inbox = 0 AND t.start_time IS NOT NULL '
      'AND t.end_time IS NOT NULL AND t.start_time < ? AND t.end_time > ?',
      variables: [Variable<String>(_iso(end)), Variable<String>(_iso(start))],
      readsFrom: {tasks},
    ).get();
    return [
      for (final row in rows)
        (
          start: DateTime.parse(row.read<String>('start_time')).toLocal(),
          status: row.read<String>('status'),
          rescheduledToId: row.readNullable<String>('rescheduled_to_id'),
          successorLive: row.read<bool>('successor_live'),
        ),
    ];
  }

  /// Start, end and status of the same tasks [getTasksBetween] returns, for
  /// callers that only add up planned minutes (Insights). Same reasoning and
  /// filter as [getStartAndStatusBetween]. Order is not specified.
  Future<
    List<
      ({
        DateTime start,
        DateTime end,
        String status,
        String? rescheduledToId,
        bool successorLive,
      })
    >
  >
  getScheduleSpansBetween(DateTime start, DateTime end) async {
    final rows = await customSelect(
      'SELECT t.start_time, t.end_time, t.status, t.rescheduled_to_id, '
      '$_successorLiveSql FROM tasks t WHERE t.deleted_at IS NULL '
      'AND t.is_inbox = 0 AND t.start_time IS NOT NULL '
      'AND t.end_time IS NOT NULL AND t.start_time < ? AND t.end_time > ?',
      variables: [Variable<String>(_iso(end)), Variable<String>(_iso(start))],
      readsFrom: {tasks},
    ).get();
    return [
      for (final row in rows)
        (
          start: DateTime.parse(row.read<String>('start_time')).toLocal(),
          end: DateTime.parse(row.read<String>('end_time')).toLocal(),
          status: row.read<String>('status'),
          rescheduledToId: row.readNullable<String>('rescheduled_to_id'),
          successorLive: row.read<bool>('successor_live'),
        ),
    ];
  }

  /// Id, start, title and status of the same tasks [getTasksBetween] returns
  /// (same filter as [getStartAndStatusBetween]), for Review search, which
  /// matches titles and needs the id and status to tell which saved reasons
  /// the Daily Review still shows. Order is not specified.
  Future<List<({String id, DateTime start, String title, String status})>>
  getStartAndTitleBetween(DateTime start, DateTime end) async {
    final rows = await customSelect(
      'SELECT t.id, t.start_time, t.title, t.status FROM tasks t '
      'WHERE t.deleted_at IS NULL '
      'AND t.is_inbox = 0 AND t.start_time IS NOT NULL '
      'AND t.end_time IS NOT NULL AND t.start_time < ? AND t.end_time > ?',
      variables: [Variable<String>(_iso(end)), Variable<String>(_iso(start))],
      readsFrom: {tasks},
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          start: DateTime.parse(row.read<String>('start_time')).toLocal(),
          title: row.read<String>('title'),
          status: row.read<String>('status'),
        ),
    ];
  }

  static const _successorLiveSql =
      'EXISTS (SELECT 1 FROM tasks s WHERE s.id = t.rescheduled_to_id '
      'AND s.deleted_at IS NULL) AS successor_live';

  /// The ids among [ids] whose rows exist and are not deleted. Callers use it
  /// to learn whether a rescheduled block's new block still exists.
  Future<Set<String>> liveTaskIds(Iterable<String> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return const <String>{};
    final live = <String>{};
    // SQLite caps bound variables; chunk large sets.
    final list = wanted.toList(growable: false);
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(
        i,
        i + 500 > list.length ? list.length : i + 500,
      );
      final rows =
          await (selectOnly(tasks)
                ..addColumns([tasks.id])
                ..where(tasks.id.isIn(chunk) & tasks.deletedAt.isNull()))
              .get();
      live.addAll(rows.map((row) => row.read(tasks.id)!));
    }
    return live;
  }

  /// Every row linked to [ids] through `rescheduled_to_id`, in either
  /// direction and including [ids] (deleted rows too), for the review's
  /// "moved" text (`reschedule_chain.dart`). UNION makes a cycle terminate.
  Future<
    List<
      ({
        String id,
        DateTime? start,
        DateTime? end,
        String? rescheduledToId,
        bool deleted,
      })
    >
  >
  getRescheduleRelatives(Iterable<String> ids) async {
    final seeds = ids.toSet().toList(growable: false);
    if (seeds.isEmpty) return const [];
    final rows = await customSelect(
      'WITH RECURSIVE chain(id) AS ('
      'SELECT id FROM tasks WHERE id IN (${List.filled(seeds.length, '?').join(', ')}) '
      'UNION SELECT t.rescheduled_to_id FROM tasks t JOIN chain c ON t.id = c.id '
      'WHERE t.rescheduled_to_id IS NOT NULL '
      'UNION SELECT t.id FROM tasks t JOIN chain c ON t.rescheduled_to_id = c.id) '
      'SELECT t.id, t.start_time, t.end_time, t.rescheduled_to_id, '
      't.deleted_at IS NOT NULL AS deleted FROM tasks t JOIN chain c ON t.id = c.id',
      variables: [for (final id in seeds) Variable<String>(id)],
      readsFrom: {tasks},
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          start: _parseDateTime(row.readNullable<String>('start_time')),
          end: _parseDateTime(row.readNullable<String>('end_time')),
          rescheduledToId: row.readNullable<String>('rescheduled_to_id'),
          deleted: row.read<bool>('deleted'),
        ),
    ];
  }

  /// The new blocks of the rescheduled rows among [rows] that still exist.
  /// Pass the result to [TaskRowPlanCounting].
  Future<Set<String>> liveSuccessorIds(Iterable<TaskRow> rows) => liveTaskIds([
    for (final row in rows)
      if (row.rescheduledToId != null &&
          row.status == TaskStatus.rescheduled.dbValue)
        row.rescheduledToId!,
  ]);

  /// Searches the schema-v6 external-content FTS index. The query is already
  /// normalized to a safe literal expression by [SearchRepository]; the
  /// value is still bound as a parameter so user text never becomes SQL.
  Future<List<TaskSearchRow>> searchTasks(
    String ftsQuery, {
    int limit = 100,
  }) async {
    if (ftsQuery.trim().isEmpty) return const <TaskSearchRow>[];
    final rows = await customSelect(
      'SELECT t.id, t.title, t.description, t.is_inbox, t.start_time, '
      't.status, t.category_id, '
      'bm25(tasks_fts) AS relevance '
      'FROM tasks_fts '
      'JOIN tasks t ON t.rowid = tasks_fts.rowid '
      'WHERE tasks_fts MATCH ? AND t.deleted_at IS NULL '
      "ORDER BY relevance ASC, COALESCE(t.start_time, '9999-12-31T23:59:59Z') ASC, "
      't.id ASC LIMIT ?',
      variables: [
        Variable<String>(ftsQuery),
        Variable<int>(limit.clamp(1, 500)),
      ],
      readsFrom: {tasks},
    ).get();
    return rows
        .map(
          (row) => TaskSearchRow(
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            description: row.readNullable<String>('description'),
            isInbox: row.read<bool>('is_inbox'),
            startTime: _parseDateTime(row.readNullable<String>('start_time')),
            status: row.read<String>('status'),
            categoryId: row.readNullable<String>('category_id'),
            relevance: row.read<double>('relevance'),
          ),
        )
        .toList(growable: false);
  }

  Expression<bool> _dayFilter(
    Tasks t,
    DateTime dayStart, {
    required DateTime dayEnd,
  }) =>
      t.deletedAt.isNull() &
      t.isInbox.equals(false) &
      t.startTime.isNotNull() &
      t.endTime.isNotNull() &
      t.startTime.isSmallerThanValue(_iso(dayEnd)) &
      t.endTime.isBiggerThanValue(_iso(dayStart));

  (DateTime start, DateTime end) _dayBounds(DateTime day) {
    final start = startOfDay(day);
    return (start, addDays(start, 1));
  }

  Future<TaskRow?> getTaskById(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<bool> updateTask(TaskRow row) async {
    final count = await (update(tasks)..where((task) => task.id.equals(row.id)))
        .write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  /// Reserved for acknowledged tombstone cleanup and migration repair. Normal
  /// application deletion and Undo use soft deletes through TaskRepository.
  Future<int> hardDeleteTask(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  String _iso(DateTime instant) => instant.toUtc().toIso8601String();
}

/// Typed result of the DAO-level FTS query. Presentation code never receives
/// raw Drift custom-select maps.
class TaskSearchRow {
  final String id;
  final String title;
  final String? description;
  final bool isInbox;
  final DateTime? startTime;
  final String status;
  final String? categoryId;
  final double relevance;

  const TaskSearchRow({
    required this.id,
    required this.title,
    required this.description,
    required this.isInbox,
    required this.startTime,
    required this.status,
    required this.categoryId,
    required this.relevance,
  });
}

/// `plan_counting.dart` applied to a full row; [liveSuccessors] comes from
/// [TaskDao.liveSuccessorIds].
extension TaskRowPlanCounting on TaskRow {
  bool countsAsTask(Set<String> liveSuccessors) => countsAsPlannedTask(
    TaskStatus.fromDb(status),
    rescheduledToId,
    successorLive: liveSuccessors.contains(rescheduledToId),
  );

  bool countsAsTime(Set<String> liveSuccessors) => countsAsPlannedTime(
    TaskStatus.fromDb(status),
    rescheduledToId,
    successorLive: liveSuccessors.contains(rescheduledToId),
  );
}

DateTime? _parseDateTime(String? value) =>
    value == null ? null : DateTime.tryParse(value)?.toLocal();
