import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../categories/data/category_repository.dart';
import '../domain/initial_sync_models.dart';

/// Measures the meaningful local Planner content of one SQLite database.
///
/// This is deliberately not "tasks table has rows". A database can contain
/// untouched built-in categories and nothing else, while a used account can
/// contain tombstones (deletion history) or a durable outbox with no live rows.
/// Untouched defaults never count as user content; live rows (except untouched
/// defaults), soft-deleted rows and pending outbox operations all do.
class PlannerDataProbe {
  PlannerDataProbe(this._db);

  static const List<String> dataTables = [
    'day_contexts',
    'categories',
    'tags',
    'recurring_rules',
    'tasks',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'subtasks',
    'task_tags',
    'timer_sessions',
  ];

  final AppDatabase _db;

  Future<LocalDataSummary> inspect() async {
    var live = 0;
    var tombstoned = 0;
    for (final table in dataTables) {
      final row =
          await _db
              .customSelect(
                'SELECT '
                'SUM(CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END) AS live, '
                'SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END) AS deleted '
                'FROM $table',
              )
              .getSingle();
      live += row.readNullable<int>('live') ?? 0;
      tombstoned += row.readNullable<int>('deleted') ?? 0;
    }
    live -= await _untouchedDefaultCategoryCount();
    final pending = await _pendingOperationCount();
    return LocalDataSummary(
      liveRecords: live < 0 ? 0 : live,
      tombstonedRecords: tombstoned,
      pendingOperations: pending,
    );
  }

  /// Durable outbox states that represent unacknowledged local work.
  ///
  /// Shared with [InitialSyncStateStore] so the restore completion gate and the
  /// probe can never disagree about what counts as local Planner work.
  static const String activeOperationStatesSql =
      "('pending', 'error', 'in_flight', 'conflict')";

  static const _activeOperationStates = activeOperationStatesSql;

  /// Durable outbox entries, excluding the seed inserts of untouched built-in
  /// categories. Those rows are application-created defaults, so a database
  /// that was seeded by an earlier build still reads as "no user content".
  Future<int> _pendingOperationCount() async {
    final row =
        await _db
            .customSelect(
              'SELECT COUNT(*) AS count FROM sync_log '
              'WHERE state IN $_activeOperationStates',
            )
            .getSingle();
    var count = row.read<int>('count');
    for (final definition in CategoryRepository.defaultCategoryDefinitions) {
      final seeded =
          await _db
              .customSelect(
                'SELECT COUNT(*) AS count FROM categories c WHERE '
                'c.id = ? AND c.name = ? AND c.color_hex = ? '
                'AND c.sort_order = ? AND c.is_focus = ? '
                'AND c.deleted_at IS NULL AND c.server_version IS NULL '
                'AND EXISTS (SELECT 1 FROM sync_log l WHERE '
                "l.table_name = 'categories' AND l.record_id = c.id "
                "AND l.operation = 'insert' AND l.state IN "
                '$_activeOperationStates)',
                variables: [
                  Variable<String>(
                    CategoryRepository.defaultCategoryId(definition.key),
                  ),
                  Variable<String>(definition.name),
                  Variable<String>(definition.colorHex),
                  Variable<int>(definition.sortOrder),
                  Variable<int>(definition.isFocus ? 1 : 0),
                ],
              )
              .getSingle();
      count -= seeded.read<int>('count');
    }
    return count < 0 ? 0 : count;
  }

  /// True when the durable outbox holds any unacknowledged local operation.
  ///
  /// This is the provenance-safe signal for "user-authored Planner work
  /// exists". Local domain writes enqueue operations through the SQLite
  /// triggers, while remote apply and migration repair run with the outbound
  /// trigger suppressed, so the signal can never mistake restored remote rows
  /// for local edits.
  Future<bool> hasActiveOutboxOperations() async =>
      await _pendingOperationCount() > 0;

  /// Counts live categories that are exactly one of the built-in defaults, so
  /// a freshly seeded database still reports no user content. A default the
  /// user renamed, re-colored, re-ordered or deleted is not counted here.
  Future<int> _untouchedDefaultCategoryCount() async {
    var count = 0;
    for (final definition in CategoryRepository.defaultCategoryDefinitions) {
      final row =
          await _db
              .customSelect(
                'SELECT COUNT(*) AS count FROM categories '
                'WHERE id = ? AND name = ? AND color_hex = ? AND sort_order = ? '
                'AND is_focus = ? AND deleted_at IS NULL',
                variables: [
                  Variable<String>(
                    CategoryRepository.defaultCategoryId(definition.key),
                  ),
                  Variable<String>(definition.name),
                  Variable<String>(definition.colorHex),
                  Variable<int>(definition.sortOrder),
                  Variable<int>(definition.isFocus ? 1 : 0),
                ],
              )
              .getSingle();
      count += row.read<int>('count');
    }
    return count;
  }
}
