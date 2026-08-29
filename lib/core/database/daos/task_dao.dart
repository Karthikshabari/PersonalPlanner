import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tasks_table.dart';
import '../../utils/date_utils.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  /// Day tasks in chronological order — callers (timeline block layout,
  /// conflict planning) rely on start_time ordering.
  Stream<List<TaskRow>> watchTasksForDay(DateTime day) =>
      (select(tasks)
            ..where((t) => _dayFilter(t, day, dayEnd: _nextDay(day)))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .watch();

  /// One-shot variant of [watchTasksForDay] used by stats computation
  /// (planner.md Chunk 5 #9).
  Future<List<TaskRow>> getTasksForDay(DateTime day) =>
      (select(tasks)
            ..where((t) => _dayFilter(t, day, dayEnd: _nextDay(day)))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  /// Scheduled non-deleted tasks intersecting [start, end) — used for
  /// day/week-level aggregation.
  Future<List<TaskRow>> getTasksBetween(DateTime start, DateTime end) =>
      (select(tasks)
            ..where((t) => _dayFilter(t, start, dayEnd: end))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  /// Searches the schema-v6 external-content FTS index. The query is already
  /// normalized to a safe literal expression by [SearchRepository]; the
  /// value is still bound as a parameter so user text never becomes SQL.
  Future<List<TaskSearchRow>> searchTasks(
    String ftsQuery, {
    int limit = 100,
  }) async {
    if (ftsQuery.trim().isEmpty) return const <TaskSearchRow>[];
    final rows = await customSelect(
      'SELECT t.id, t.title, t.start_time, t.status, t.category_id, '
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

  DateTime _nextDay(DateTime day) => addDays(day, 1);

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
  final DateTime? startTime;
  final String status;
  final String? categoryId;
  final double relevance;

  const TaskSearchRow({
    required this.id,
    required this.title,
    required this.startTime,
    required this.status,
    required this.categoryId,
    required this.relevance,
  });
}

DateTime? _parseDateTime(String? value) =>
    value == null ? null : DateTime.tryParse(value)?.toLocal();
