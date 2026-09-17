// TableMigration is Drift's supported SQLite table-rebuild primitive. Schema
// v6 needs it to add foreign keys and remove legacy inline uniqueness safely.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/category_dao.dart';
import 'daos/recurring_rule_dao.dart';
import 'daos/review_dao.dart';
import 'daos/stats_dao.dart';
import 'daos/sync_dao.dart';
import 'daos/subtask_dao.dart';
import 'daos/tag_dao.dart';
import 'daos/task_dao.dart';
import 'daos/template_dao.dart';
import 'daos/timer_dao.dart';
import 'converters.dart';
import '../utils/task_time_metrics.dart';
import '../utils/uuid.dart';
import '../utils/missed_at.dart';
import 'tables/app_settings_table.dart';
import 'tables/categories_table.dart';
import 'tables/day_contexts_table.dart';
import 'tables/daily_reviews_table.dart';
import 'tables/daily_stats_cache_table.dart';
import 'tables/recurring_rules_table.dart';
import 'tables/subtasks_table.dart';
import 'tables/tags_table.dart';
import 'tables/tasks_table.dart';
import 'tables/task_templates_table.dart';
import 'tables/timer_sessions_table.dart';
import 'tables/weekly_reviews_table.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Categories,
    DayContexts,
    AppSettings,
    Subtasks,
    Tags,
    TaskTags,
    RecurringRules,
    TaskTemplates,
    DailyReviews,
    WeeklyReviews,
    DailyStatsCache,
    TimerSessions,
    SyncLog,
    SyncConflicts,
    SyncState,
  ],
  daos: [
    TaskDao,
    CategoryDao,
    SubtaskDao,
    TagDao,
    RecurringRuleDao,
    TemplateDao,
    ReviewDao,
    StatsDao,
    TimerDao,
    SyncDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// SQLite sync triggers append to sync_log after domain writes, but those
  /// trigger-side writes are invisible to Drift's stream tracker. Propagate
  /// each domain update to the outbox table so an already-open pending stream
  /// wakes immediately. The remote apply marker still suppresses actual
  /// trigger inserts; an empty wake is harmless and lets the engine re-check
  /// durable state without polling.
  @override
  StreamQueryUpdateRules get streamUpdateRules => StreamQueryUpdateRules([
    ...super.streamUpdateRules.rules,
    for (final table in const [
      'tasks',
      'categories',
      'day_contexts',
      'subtasks',
      'tags',
      'task_tags',
      'recurring_rules',
      'task_templates',
      'daily_reviews',
      'weekly_reviews',
      'timer_sessions',
    ])
      WritePropagation(
        on: TableUpdateQuery.onTableName(table),
        result: [TableUpdate('sync_log', kind: UpdateKind.insert)],
      ),
  ]);

  /// Opens the stable anonymous database or an account-isolated database.
  ///
  /// [accountId] is the canonical account scope storage id
  /// (`project_<projectRef>__user_<authUserId>` for a provisioned user-owned
  /// backend, or the bare auth user id for the historical compile-time
  /// developer backend). It is never user-entered text, and it is validated
  /// against those two shapes before it can reach a file path.
  static Future<AppDatabase> open({String? accountId}) async {
    // Account adoption intentionally opens the anonymous and authenticated
    // databases at the same time. They use different file executors, so the
    // generated-database warning about multiple instances is not applicable.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await getApplicationSupportDirectory();
    return AppDatabase(
      _openConnection(
        p.join(dir.path, databaseFileNameFor(accountId: accountId)),
      ),
    );
  }

  /// File name of the anonymous database. Unchanged since the first release.
  static const String anonymousDatabaseFileName = 'personal_planner.sqlite3';

  /// Deterministic file name for the anonymous or account-isolated database.
  ///
  /// The provisioned scope keeps `projectRef` and `authUserId` in the name, so
  /// the same auth user id in two different Supabase projects resolves to two
  /// different files.
  static String databaseFileNameFor({String? accountId}) => accountId == null
      ? anonymousDatabaseFileName
      : 'personal_planner_account_${_safeAccountId(accountId)}.sqlite3';

  static String _safeAccountId(String accountId) {
    final normalized = accountId.toLowerCase();
    if (_legacyAccountIdShape.hasMatch(normalized) ||
        _projectScopedAccountIdShape.hasMatch(normalized)) {
      return normalized;
    }
    throw ArgumentError(
      'Account ID must be a Supabase Auth user id or a project-scoped '
      'account id',
    );
  }

  /// Historical compile-time developer backend: the auth user id alone.
  static final RegExp _legacyAccountIdShape = RegExp(r'^[0-9a-f-]{36}$');

  /// Provisioned user-owned backend: `project_<ref>__user_<authUserId>`.
  ///
  /// Both parts are fixed-shape, so the name is unambiguous and contains no
  /// path separator, no whitespace, and no user-entered text.
  static final RegExp _projectScopedAccountIdShape = RegExp(
    r'^project_[a-z0-9]{20}__user_[0-9a-f-]{36}$',
  );

  static QueryExecutor _openConnection(String path) =>
      NativeDatabase.createInBackground(
        File(path),
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      );

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
      await _createFts();
      await _createSyncIndexes();
      await _createSyncTriggers();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(subtasks);
        await m.createTable(tags);
        await m.createTable(taskTags);
      }
      if (from < 3) {
        await m.createTable(recurringRules);
        await m.createTable(taskTemplates);
      }
      if (from < 4) {
        await m.createTable(dailyReviews);
        await m.createTable(weeklyReviews);
        await m.createTable(dailyStatsCache);
      }
      if (from < 5) {
        await m.createTable(timerSessions);
      }
      if (from < 6) {
        await _migrateToV6(m, from);
        // FTS belongs to the v6 migration. A v6 -> v7 sync-only upgrade must
        // leave the already-released virtual table and triggers untouched.
        await _createFts();
      }
      if (from < 7) {
        await _migrateToV7(m, from);
      }
      if (from < 8) {
        await _migrateToV8(m);
      }
      if (from < 9) {
        await _addColumnIfMissing(
          m,
          'tasks',
          tasks,
          tasks.recurrenceRemovalReason,
        );
      }
      // Some development v8 clients opened before every Foundation table and
      // column was present. Restore the coordinated v8 shape idempotently.
      await _ensureDayContextTable();
      // Indexes are idempotent — always ensure they exist.
      await _createIndexes();
      await _createSyncIndexes();
      await _createSyncTriggers();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // R3 adds a parentless table without advancing the already-established
      // v8 number. This idempotent guard upgrades databases that were opened
      // by the earlier v8 client before Day Context existed.
      await _ensureDayContextTable();
      await _ensureTimeAccountingSchema();
      await _createIndexes();
      await _createSyncIndexes();
      await _createSyncTriggers();
      await _normalizeExistingInstants();
      await _normalizeExistingTaskEstimates();
    },
  );

  /// Repairs timestamp text written by older sync clients. SQLite compares
  /// TEXT lexically, so equivalent offset and UTC forms must be normalized
  /// before any range query runs. Malformed values are left untouched and
  /// copied to the recovery ledger for a later repair tool.
  Future<void> _normalizeExistingInstants() async {
    const fields = <String, Map<String, String>>{
      'tasks': {
        'start_time': 'instant',
        'end_time': 'instant',
        'missed_at': 'minute',
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'categories': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'subtasks': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'tags': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'task_tags': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'recurring_rules': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'task_templates': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'daily_reviews': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'weekly_reviews': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'timer_sessions': {
        'started_at': 'instant',
        'ended_at': 'instant',
        'running_since': 'instant',
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
      'day_contexts': {
        'created_at': 'instant',
        'updated_at': 'instant',
        'deleted_at': 'instant',
      },
    };
    const primaryKeys = <String, String>{
      'task_tags': 'task_id = ? AND tag_id = ?',
    };
    final hasRecovery = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'planner_migration_recovery'",
    ).getSingleOrNull();
    final malformed =
        <
          ({
            String table,
            String key,
            String column,
            String raw,
            Map<String, Object?> row,
          })
        >[];
    final previousApplyMode = await customSelect(
      "SELECT value FROM app_settings WHERE key = 'sync.apply_mode'",
    ).getSingleOrNull();
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('sync.apply_mode', '1')",
    );
    try {
      for (final entry in fields.entries) {
        final table = entry.key;
        final columns = entry.value;
        final rows = await customSelect('SELECT * FROM $table').get();
        for (final row in rows) {
          final key = table == 'task_tags'
              ? '${row.read<String>('task_id')}:${row.read<String>('tag_id')}'
              : row.read<String>('id');
          for (final field in columns.entries) {
            final raw = row.readNullable<String>(field.key);
            if (raw == null) continue;
            final canonical = field.value == 'minute'
                ? MissedAtCodec.normalize(raw)
                : DateTime.tryParse(raw)?.toUtc().toIso8601String();
            if (canonical == null) {
              malformed.add((
                table: table,
                key: key,
                column: field.key,
                raw: raw,
                row: Map<String, Object?>.from(row.data),
              ));
              continue;
            }
            if (canonical == raw) continue;
            final where = primaryKeys[table] ?? 'id = ?';
            final variables = table == 'task_tags'
                ? <Object>[
                    canonical,
                    row.read<String>('task_id'),
                    row.read<String>('tag_id'),
                  ]
                : <Object>[canonical, key];
            await customStatement(
              'UPDATE $table SET ${field.key} = ? WHERE $where',
              variables,
            );
          }
        }
      }
      if (malformed.isEmpty || hasRecovery == null) return;
      for (final item in malformed) {
        await customStatement(
          'INSERT OR IGNORE INTO planner_migration_recovery '
          '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            'timestamp:${item.table}:${item.key}:${item.column}',
            item.table,
            item.key,
            jsonEncode({
              'row': item.row,
              'column': item.column,
              'value': item.raw,
            }),
            'Unparseable timestamp retained during normalization',
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
    } finally {
      if (previousApplyMode == null) {
        await customStatement(
          "DELETE FROM app_settings WHERE key = 'sync.apply_mode'",
        );
      } else {
        await customStatement(
          "UPDATE app_settings SET value = ? WHERE key = 'sync.apply_mode'",
          [previousApplyMode.read<String>('value')],
        );
      }
    }
  }

  /// Schema-v6 is the audit stabilization migration. It upgrades every
  /// released v1-v5 database without resetting user data, then rebuilds the
  /// tables whose constraints or foreign keys changed.
  Future<void> _migrateToV6(Migrator m, int originalVersion) async {
    await _normalizeLegacyRows();

    await m.alterTable(
      TableMigration(categories, newColumns: [categories.serverVersion]),
    );
    await m.alterTable(
      TableMigration(
        tasks,
        // These fields were introduced after the v1-v5 task schema too. They
        // must be declared as new during this table rebuild; otherwise SQLite
        // treats an absent double-quoted column as a string literal and the
        // v8 check constraint rejects the legacy copy before normalization.
        newColumns: [
          tasks.manualDurationAdjustmentMin,
          tasks.manualActualSet,
          tasks.inboxContentVersion,
          tasks.dueDate,
          tasks.planTitleHistoryJson,
          tasks.displayPlanChangeId,
          tasks.recurrenceRemovalReason,
          tasks.serverVersion,
        ],
      ),
    );
    // Tables introduced while upgrading directly from an older version were
    // just created from the v6 definitions and must not be rebuilt again.
    if (originalVersion >= 2) {
      await m.alterTable(
        TableMigration(subtasks, newColumns: [subtasks.serverVersion]),
      );
      await m.alterTable(
        TableMigration(tags, newColumns: [tags.serverVersion]),
      );
      await m.alterTable(
        TableMigration(
          taskTags,
          newColumns: [
            taskTags.updatedAt,
            taskTags.deletedAt,
            taskTags.revision,
            taskTags.serverVersion,
          ],
          columnTransformer: {taskTags.updatedAt: taskTags.createdAt},
        ),
      );
    }
    if (originalVersion >= 3) {
      await m.alterTable(
        TableMigration(
          recurringRules,
          newColumns: [recurringRules.serverVersion],
        ),
      );
      await m.alterTable(
        TableMigration(
          taskTemplates,
          newColumns: [taskTemplates.serverVersion],
        ),
      );
    }
    if (originalVersion >= 4) {
      await m.alterTable(
        TableMigration(dailyReviews, newColumns: [dailyReviews.serverVersion]),
      );
      await m.alterTable(
        TableMigration(
          weeklyReviews,
          newColumns: [weeklyReviews.serverVersion],
        ),
      );
      await m.alterTable(
        TableMigration(
          dailyStatsCache,
          newColumns: [
            dailyStatsCache.plannedTasks,
            dailyStatsCache.inProgressTasks,
          ],
        ),
      );
    }
    if (originalVersion >= 5) {
      await m.alterTable(
        TableMigration(
          timerSessions,
          newColumns: [
            timerSessions.state,
            timerSessions.runningSince,
            timerSessions.workIntervalsJson,
            timerSessions.ownerDeviceId,
            timerSessions.serverVersion,
          ],
        ),
      );
    }

    await _rejectUnsafeActiveDuplicates();

    final violations = await customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw StateError(
        'Schema v6 migration left ${violations.length} foreign-key violation(s)',
      );
    }
  }

  /// Adds the v7 remote-version metadata only to tables present in the source
  /// database. Tables introduced during the same upgrade already use the
  /// current definitions and must not be rebuilt twice.
  Future<void> _migrateToV7(Migrator m, int originalVersion) async {
    await m.createTable(syncLog);
    await m.createTable(syncConflicts);
    await m.createTable(syncState);

    await _addServerVersionIfMissing(
      m,
      'categories',
      categories,
      categories.serverVersion,
    );
    await _addServerVersionIfMissing(m, 'tasks', tasks, tasks.serverVersion);
    if (originalVersion >= 2) {
      await _addServerVersionIfMissing(
        m,
        'subtasks',
        subtasks,
        subtasks.serverVersion,
      );
      await _addServerVersionIfMissing(m, 'tags', tags, tags.serverVersion);
      await _addServerVersionIfMissing(
        m,
        'task_tags',
        taskTags,
        taskTags.serverVersion,
      );
    }
    if (originalVersion >= 3) {
      await _addServerVersionIfMissing(
        m,
        'recurring_rules',
        recurringRules,
        recurringRules.serverVersion,
      );
      await _addServerVersionIfMissing(
        m,
        'task_templates',
        taskTemplates,
        taskTemplates.serverVersion,
      );
    }
    if (originalVersion >= 4) {
      await _addServerVersionIfMissing(
        m,
        'daily_reviews',
        dailyReviews,
        dailyReviews.serverVersion,
      );
      await _addServerVersionIfMissing(
        m,
        'weekly_reviews',
        weeklyReviews,
        weeklyReviews.serverVersion,
      );
    }
    if (originalVersion >= 5) {
      await _addServerVersionIfMissing(
        m,
        'timer_sessions',
        timerSessions,
        timerSessions.serverVersion,
      );
    }
  }

  /// Schema-v8 installs the Inbox content/due-date contract and repairs the
  /// existing schedule projection. Legacy explicit Inbox rows are transformed
  /// once, including tombstones, with their exact source retained in the
  /// recovery ledger so an interrupted upgrade is retryable and auditable.
  Future<void> _migrateToV8(Migrator m) async {
    await m.createTable(dayContexts);
    await _addColumnIfMissing(m, 'tasks', tasks, tasks.inboxContentVersion);
    await _addColumnIfMissing(m, 'tasks', tasks, tasks.dueDate);
    await _addColumnIfMissing(m, 'tasks', tasks, tasks.manualActualSet);
    await _addColumnIfMissing(m, 'tasks', tasks, tasks.planTitleHistoryJson);
    await _addColumnIfMissing(m, 'tasks', tasks, tasks.displayPlanChangeId);
    await _addColumnIfMissing(
      m,
      'timer_sessions',
      timerSessions,
      timerSessions.state,
    );
    await _addColumnIfMissing(
      m,
      'timer_sessions',
      timerSessions,
      timerSessions.runningSince,
    );
    await _addColumnIfMissing(
      m,
      'timer_sessions',
      timerSessions,
      timerSessions.workIntervalsJson,
    );
    await _addColumnIfMissing(
      m,
      'timer_sessions',
      timerSessions,
      timerSessions.ownerDeviceId,
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS planner_migration_recovery (
        recovery_id TEXT NOT NULL PRIMARY KEY,
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        reason TEXT NOT NULL,
        recovered_at TEXT NOT NULL
      )
    ''');
    final previousApplyMode = await customSelect(
      "SELECT value FROM app_settings WHERE key = 'sync.apply_mode'",
    ).getSingleOrNull();
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('sync.apply_mode', '1')",
    );
    try {
      // v7 databases already have triggers. Recreate them after this method
      // so migration repairs cannot create semantic sync operations.
      await _dropSyncTriggers();
      final legacyRows = await customSelect(
        'SELECT id, title, description, is_inbox, inbox_content_version, '
        'deleted_at FROM tasks WHERE is_inbox = 1 AND inbox_content_version = 0',
      ).get();
      for (final row in legacyRows) {
        final id = row.read<String>('id');
        final title = row.read<String>('title');
        final description = row.readNullable<String>('description');
        final migratedDescription = description == null || description.isEmpty
            ? title
            : description == title
            ? description
            : '$title\n\n$description';
        await customStatement(
          'INSERT OR IGNORE INTO planner_migration_recovery '
          '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            'v8:tasks:$id',
            'tasks',
            id,
            jsonEncode({
              'id': id,
              'title': title,
              'description': description,
              'is_inbox': row.read<int>('is_inbox'),
              'inbox_content_version': row.read<int>('inbox_content_version'),
              'deleted_at': row.readNullable<String>('deleted_at'),
            }),
            'Migrated legacy explicit Inbox content without trimming',
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
        await customStatement(
          'UPDATE tasks SET description = ?, inbox_content_version = 1 '
          'WHERE id = ? AND inbox_content_version = 0',
          [migratedDescription, id],
        );
      }
      // This is the only legacy-cache-to-manual conversion boundary. It is
      // reached from an actual pre-v8 schema upgrade, never from an ordinary
      // open of a database that already advertises schema v8.
      await _migrateLegacyTimeAccounting();
    } finally {
      if (previousApplyMode == null) {
        await customStatement(
          "DELETE FROM app_settings WHERE key = 'sync.apply_mode'",
        );
      } else {
        await customStatement(
          "UPDATE app_settings SET value = ? WHERE key = 'sync.apply_mode'",
          [previousApplyMode.read<String>('value')],
        );
      }
    }
  }

  Future<void> _migrateLegacyTimeAccounting() async {
    final legacyTasks = await customSelect(
      'SELECT id, actual_duration_min, manual_duration_adjustment_min, '
      'manual_actual_set FROM tasks WHERE manual_actual_set = 0 AND '
      '(actual_duration_min IS NOT NULL OR manual_duration_adjustment_min != 0)',
    ).get();
    for (final task in legacyTasks) {
      final id = task.read<String>('id');
      final actual = task.readNullable<int>('actual_duration_min');
      final adjustment = task.read<int>('manual_duration_adjustment_min');
      final completed = await customSelect(
        "SELECT COALESCE(SUM(duration_sec), 0) AS total FROM timer_sessions "
        "WHERE task_id = ? AND state = 'finished' AND ended_at IS NOT NULL "
        'AND deleted_at IS NULL',
        variables: [Variable<String>(id)],
      ).getSingle();
      final minutes = completed.read<int>('total') ~/ 60;
      // In the old representation Actual was the displayed total. Recover
      // only the signed source that explains that total over measured work.
      final inferred = actual == null ? adjustment : actual - minutes;
      await customStatement(
        'INSERT OR IGNORE INTO planner_migration_recovery '
        '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          'v8:tasks:$id',
          'tasks',
          id,
          jsonEncode(task.data),
          'Inferred one-time manual actual source from legacy displayed cache',
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      await customStatement(
        'UPDATE tasks SET manual_duration_adjustment_min = ?, '
        'manual_actual_set = 1 WHERE id = ?',
        [inferred, id],
      );
    }
  }

  /// Queues the post-transform task snapshot once, after all legacy content
  /// has been normalized. The deterministic operation ID makes a retried
  /// upgrade idempotent while leaving every historical outbox row untouched.
  Future<void> _enqueueV8TaskReconciliation(String taskId) async {
    final row = await customSelect(
      'SELECT * FROM tasks WHERE id = ?',
      variables: [Variable<String>(taskId)],
    ).getSingleOrNull();
    if (row == null) return;

    final operationId = generateDeterministicUuid(
      'v8-foundation-final:tasks:$taskId',
    );
    final priorOperations = await customSelect(
      'SELECT operation_id FROM sync_log '
      'WHERE table_name = ? AND record_id = ? LIMIT 1',
      variables: [Variable<String>('tasks'), Variable<String>(taskId)],
    ).get();
    final serverVersion = row.readNullable<int>('server_version');
    final deletedAt = row.readNullable<String>('deleted_at');
    final operation = deletedAt != null
        ? (serverVersion == null && priorOperations.isEmpty
              ? 'insert'
              : 'delete')
        : (serverVersion == null && priorOperations.isEmpty
              ? 'insert'
              : 'update');

    final latest = await customSelect(
      'SELECT MAX(created_at) AS latest_created_at FROM sync_log '
      'WHERE table_name = ? AND record_id = ?',
      variables: [Variable<String>('tasks'), Variable<String>(taskId)],
    ).getSingle();
    var createdAt = DateTime.now().toUtc();
    final latestRaw = latest.readNullable<String>('latest_created_at');
    final latestAt = DateTime.tryParse(latestRaw ?? '')?.toUtc();
    if (latestAt != null && !createdAt.isAfter(latestAt)) {
      createdAt = latestAt.add(const Duration(microseconds: 1));
    }
    final payloadMap = Map<String, Object?>.from(row.data)
      ..['_planner_payload_version'] = 2;
    final payload = jsonEncode(payloadMap);
    await customStatement(
      'INSERT OR IGNORE INTO sync_log('
      'operation_id, table_name, record_id, operation, expected_server_version, '
      'payload, state, attempt_count, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        operationId,
        'tasks',
        taskId,
        operation,
        serverVersion,
        payload,
        'pending',
        0,
        createdAt.toIso8601String(),
        createdAt.toIso8601String(),
      ],
    );
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    String tableName,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final columns = await customSelect('PRAGMA table_info("$tableName")').get();
    if (!columns.any((row) => row.read<String>('name') == column.$name)) {
      await m.addColumn(table, column);
    }
  }

  /// Repairs stale compatibility estimates whenever a database is opened.
  /// This covers interrupted imports and legacy rows as well as the v7 -> v8
  /// migration, without changing task revisions or generating sync outbox
  /// entries for a cache-only field.
  Future<void> _normalizeExistingTaskEstimates() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS planner_migration_recovery (
        recovery_id TEXT NOT NULL PRIMARY KEY,
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        reason TEXT NOT NULL,
        recovered_at TEXT NOT NULL
      )
    ''');
    final previousApplyMode = await customSelect(
      "SELECT value FROM app_settings WHERE key = 'sync.apply_mode'",
    ).getSingleOrNull();
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('sync.apply_mode', '1')",
    );
    try {
      final rows = await customSelect(
        'SELECT id, start_time, end_time, estimated_duration_min, is_inbox '
        'FROM tasks',
      ).get();
      for (final row in rows) {
        final id = row.read<String>('id');
        final rawStart = row.readNullable<String>('start_time');
        final rawEnd = row.readNullable<String>('end_time');
        final oldEstimate = row.readNullable<int>('estimated_duration_min');
        final isInbox = row.read<int>('is_inbox') == 1;
        final start = DateTime.tryParse(rawStart ?? '');
        final end = DateTime.tryParse(rawEnd ?? '');
        final expected = isInbox
            ? null
            : TaskTimeMetrics.plannedMinutes(start, end);
        final clearsInboxSchedule =
            isInbox && (rawStart != null || rawEnd != null);
        if (!clearsInboxSchedule && oldEstimate == expected) continue;

        await customStatement(
          'INSERT OR IGNORE INTO planner_migration_recovery '
          '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            'v8:tasks:$id',
            'tasks',
            id,
            jsonEncode({
              'id': id,
              'start_time': rawStart,
              'end_time': rawEnd,
              'estimated_duration_min': oldEstimate,
              'is_inbox': isInbox,
            }),
            'Repaired task scheduling projection during schema normalization',
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
        if (isInbox) {
          await customStatement(
            'UPDATE tasks SET start_time = NULL, end_time = NULL, '
            'estimated_duration_min = NULL WHERE id = ?',
            [id],
          );
        } else {
          await customStatement(
            'UPDATE tasks SET estimated_duration_min = ? WHERE id = ?',
            [expected, id],
          );
        }
      }
    } finally {
      if (previousApplyMode == null) {
        await customStatement(
          "DELETE FROM app_settings WHERE key = 'sync.apply_mode'",
        );
      } else {
        await customStatement(
          "UPDATE app_settings SET value = ? WHERE key = 'sync.apply_mode'",
          [previousApplyMode.read<String>('value')],
        );
      }
    }
  }

  Future<void> _dropSyncTriggers() async {
    const tables = [
      'tasks',
      'categories',
      'subtasks',
      'tags',
      'task_tags',
      'recurring_rules',
      'task_templates',
      'daily_reviews',
      'weekly_reviews',
      'timer_sessions',
      'day_contexts',
    ];
    for (final table in tables) {
      await customStatement('DROP TRIGGER IF EXISTS sync_${table}_insert');
      await customStatement('DROP TRIGGER IF EXISTS sync_${table}_update');
      await customStatement('DROP TRIGGER IF EXISTS sync_${table}_delete');
    }
  }

  Future<void> _addServerVersionIfMissing(
    Migrator m,
    String tableName,
    TableInfo table,
    GeneratedColumn<int> column,
  ) async {
    final columns = await customSelect('PRAGMA table_info("$tableName")').get();
    final existing = columns.map((row) => row.read<String>('name')).toSet();
    // A v6 database can be upgraded directly to v7 while still lacking the
    // v8 task fields. Include every absent current column in the same rebuild
    // so legacy values are supplied by their declared defaults/nullability.
    final missing = [
      for (final candidate in table.$columns)
        if (!existing.contains(candidate.$name)) candidate,
    ];
    if (missing.isNotEmpty &&
        missing.any((candidate) => candidate.$name == column.$name)) {
      await m.alterTable(TableMigration(table, newColumns: missing));
    }
  }

  Future<void> _normalizeLegacyRows() async {
    // Foreign-key hardening must never make legacy child data unrecoverable.
    // This local table is intentionally outside the application model: it is
    // a migration ledger that can be exported or repaired by a later tool.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS planner_migration_recovery (
        recovery_id TEXT NOT NULL PRIMARY KEY,
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        reason TEXT NOT NULL,
        recovered_at TEXT NOT NULL
      )
    ''');
    await _captureOrphanRows(
      table: 'task_tags',
      rowId: "task_id || ':' || tag_id",
      where:
          'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_tags.task_id) '
          'OR NOT EXISTS (SELECT 1 FROM tags g WHERE g.id = task_tags.tag_id)',
      reason: 'Missing task or tag parent during schema upgrade',
      requiredTables: const ['task_tags', 'tasks', 'tags'],
    );
    await _captureOrphanRows(
      table: 'subtasks',
      rowId: 'id',
      where: 'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = subtasks.task_id)',
      reason: 'Missing task parent during schema upgrade',
      requiredTables: const ['subtasks', 'tasks'],
    );
    await _captureOrphanRows(
      table: 'timer_sessions',
      rowId: 'id',
      where: 'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = timer_sessions.task_id)',
      reason: 'Missing task parent during schema upgrade',
      requiredTables: const ['timer_sessions', 'tasks'],
    );

    // Optional references can be repaired without losing their owning row.
    await _customStatementIfTables(
      ['tasks', 'categories'],
      'UPDATE tasks SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = tasks.category_id)',
    );
    await _customStatementIfTables(
      ['tasks', 'recurring_rules'],
      'UPDATE tasks SET recurring_rule_id = NULL '
      'WHERE recurring_rule_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM recurring_rules r WHERE r.id = tasks.recurring_rule_id)',
    );
    await _customStatementIfTables(
      ['tasks'],
      'UPDATE tasks SET rescheduled_from_id = NULL '
      'WHERE rescheduled_from_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks parent WHERE parent.id = tasks.rescheduled_from_id)',
    );
    await _customStatementIfTables(
      ['tasks'],
      'UPDATE tasks SET rescheduled_to_id = NULL '
      'WHERE rescheduled_to_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM tasks child WHERE child.id = tasks.rescheduled_to_id)',
    );
    await _customStatementIfTables(
      ['recurring_rules', 'categories'],
      'UPDATE recurring_rules SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = recurring_rules.category_id)',
    );
    await _customStatementIfTables(
      ['task_templates', 'categories'],
      'UPDATE task_templates SET category_id = NULL '
      'WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM categories c WHERE c.id = task_templates.category_id)',
    );

    // Child rows without a parent are retained in planner_migration_recovery
    // above before constraint hardening removes them from the live tables.
    await _customStatementIfTables(
      ['task_tags', 'tasks', 'tags'],
      'DELETE FROM task_tags WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_tags.task_id) '
      'OR NOT EXISTS (SELECT 1 FROM tags g WHERE g.id = task_tags.tag_id)',
    );
    await _customStatementIfTables(
      ['subtasks', 'tasks'],
      'DELETE FROM subtasks WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = subtasks.task_id)',
    );
    await _customStatementIfTables(
      ['timer_sessions', 'tasks'],
      'DELETE FROM timer_sessions WHERE '
      'NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = timer_sessions.task_id)',
    );

    // Preserve the editor's historical overnight interpretation before the
    // database starts enforcing end > start. New overnight writes are rejected.
    await _customStatementIfTables(
      ['tasks'],
      "UPDATE tasks SET end_time = strftime('%Y-%m-%dT%H:%M:%fZ', end_time, '+1 day') "
      'WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time',
    );
    await _customStatementIfTables(
      ['tasks'],
      'UPDATE tasks SET priority = MIN(4, MAX(0, priority)), '
      "status = CASE WHEN status IN ('planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled') THEN status ELSE 'planned' END, "
      'estimated_duration_min = CASE WHEN estimated_duration_min > 0 THEN estimated_duration_min ELSE NULL END, '
      'actual_duration_min = CASE WHEN actual_duration_min >= 0 THEN actual_duration_min ELSE NULL END',
    );
    await _customStatementIfTables(
      ['categories'],
      "UPDATE categories SET color_hex = '#4285F4' "
      "WHERE color_hex NOT GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'",
    );
    await _customStatementIfTables([
      'categories',
    ], 'UPDATE categories SET sort_order = MAX(0, sort_order)');
    await _customStatementIfTables([
      'subtasks',
    ], 'UPDATE subtasks SET sort_order = MAX(0, sort_order)');
    await _customStatementIfTables(
      ['recurring_rules'],
      "UPDATE recurring_rules SET duration_min = MAX(1, duration_min), "
      "priority = MIN(4, MAX(0, priority)), "
      "start_time_of_day = CASE WHEN start_time_of_day GLOB '[01][0-9]:[0-5][0-9]' OR start_time_of_day GLOB '2[0-3]:[0-5][0-9]' THEN start_time_of_day ELSE '09:00' END",
    );
    await _customStatementIfTables(
      ['task_templates'],
      'UPDATE task_templates SET duration_min = MAX(1, duration_min), '
      'priority = MIN(4, MAX(0, priority))',
    );
    await _customStatementIfTables(
      ['daily_reviews'],
      'UPDATE daily_reviews SET '
      'energy_level = CASE WHEN energy_level BETWEEN 1 AND 5 THEN energy_level ELSE NULL END, '
      'productivity_rating = CASE WHEN productivity_rating BETWEEN 1 AND 5 THEN productivity_rating ELSE NULL END, '
      'planning_accuracy_rating = CASE WHEN planning_accuracy_rating BETWEEN 1 AND 5 THEN planning_accuracy_rating ELSE NULL END',
    );
    await _customStatementIfTables(
      ['weekly_reviews'],
      'UPDATE weekly_reviews SET overall_rating = '
      'CASE WHEN overall_rating BETWEEN 1 AND 5 THEN overall_rating ELSE NULL END',
    );
    await _customStatementIfTables(
      ['timer_sessions'],
      'UPDATE timer_sessions SET duration_sec = MAX(0, duration_sec), '
      'ended_at = CASE WHEN ended_at IS NOT NULL AND ended_at < started_at '
      'THEN started_at ELSE ended_at END',
    );

    // A previous service-level race could leave more than one open session.
    // Keep the newest and finalize every older one at the next session start.
    await _customStatementIfTables(
      ['timer_sessions'],
      'UPDATE timer_sessions AS current SET '
      'ended_at = COALESCE((SELECT MIN(newer.started_at) FROM timer_sessions newer '
      'WHERE newer.ended_at IS NULL AND newer.deleted_at IS NULL '
      'AND (newer.started_at > current.started_at OR '
      '(newer.started_at = current.started_at AND newer.id > current.id))), current.started_at), '
      'duration_sec = MAX(0, CAST(strftime(\'%s\', COALESCE((SELECT MIN(newer.started_at) '
      'FROM timer_sessions newer WHERE newer.ended_at IS NULL AND newer.deleted_at IS NULL '
      'AND (newer.started_at > current.started_at OR '
      '(newer.started_at = current.started_at AND newer.id > current.id))), current.started_at)) AS INTEGER) '
      '- CAST(strftime(\'%s\', current.started_at) AS INTEGER)) '
      'WHERE current.ended_at IS NULL AND current.deleted_at IS NULL '
      'AND current.id != (SELECT id FROM timer_sessions '
      'WHERE ended_at IS NULL AND deleted_at IS NULL '
      'ORDER BY started_at DESC, id DESC LIMIT 1)',
    );
  }

  Future<void> _captureOrphanRows({
    required String table,
    required String rowId,
    required String where,
    required String reason,
    required List<String> requiredTables,
  }) async {
    for (final tableName in requiredTables) {
      final exists = await customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$tableName'",
      ).getSingleOrNull();
      if (exists == null) return;
    }
    final rows = await customSelect('SELECT * FROM $table WHERE $where').get();
    for (final row in rows) {
      final rowIdValue = table == 'task_tags'
          ? '${row.data['task_id']}:${row.data['tag_id']}'
          : '${row.data['id']}';
      await customStatement(
        'INSERT OR REPLACE INTO planner_migration_recovery '
        '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          '$table:$rowIdValue',
          table,
          rowIdValue,
          jsonEncode(row.data),
          reason,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  }

  Future<void> _customStatementIfTables(
    Iterable<String> tableNames,
    String statement,
  ) async {
    for (final tableName in tableNames) {
      final exists = await customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$tableName'",
      ).getSingleOrNull();
      if (exists == null) return;
    }
    await customStatement(statement);
  }

  Future<void> _rejectUnsafeActiveDuplicates() async {
    final duplicateQueries = <String, String>{
      'tag names': 'SELECT name FROM tags WHERE deleted_at IS NULL GROUP BY name HAVING COUNT(*) > 1 LIMIT 1',
      'daily review dates': 'SELECT date FROM daily_reviews WHERE deleted_at IS NULL GROUP BY date HAVING COUNT(*) > 1 LIMIT 1',
      'weekly review weeks': 'SELECT week_start_date FROM weekly_reviews WHERE deleted_at IS NULL GROUP BY week_start_date HAVING COUNT(*) > 1 LIMIT 1',
    };
    for (final entry in duplicateQueries.entries) {
      final duplicate = await customSelect(entry.value).getSingleOrNull();
      if (duplicate != null) {
        throw StateError(
          'Schema v6 migration cannot continue: duplicate active ${entry.key} '
          'exist. Delete or tombstone the duplicate row(s), then retry.',
        );
      }
    }
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_day ON tasks (start_time, end_time) WHERE deleted_at IS NULL AND is_inbox = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_inbox ON tasks (is_inbox, status) WHERE deleted_at IS NULL',
    );
    await customStatement('DROP INDEX IF EXISTS idx_tasks_overdue');
    await customStatement(
      'CREATE INDEX idx_tasks_overdue ON tasks (end_time, status, missed_at) WHERE deleted_at IS NULL AND is_inbox = 0 AND status IN (\'planned\', \'in_progress\')',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_overlap ON tasks (start_time, end_time, status) WHERE deleted_at IS NULL AND is_inbox = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_sync ON tasks (sync_status) WHERE sync_status != 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_category_date ON tasks (category_id, start_time) WHERE deleted_at IS NULL AND is_inbox = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_recurring ON tasks (recurring_rule_id, start_time) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks (task_id, sort_order) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_timer_sessions_task ON timer_sessions (task_id, started_at) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_active ON tags (name) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_reviews_date_active ON daily_reviews (date) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reviews_week_active ON weekly_reviews (week_start_date) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_day_contexts_date ON day_contexts (date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_task_tags_task_active ON task_tags (task_id, tag_id) WHERE deleted_at IS NULL',
    );
    await customStatement('DROP INDEX IF EXISTS idx_timer_one_active');
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_timer_one_running_owner ON timer_sessions (owner_device_id) WHERE state = 'running' AND deleted_at IS NULL AND owner_device_id IS NOT NULL",
    );
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_timer_one_unfinished_owner_task ON timer_sessions (owner_device_id, task_id) WHERE state IN ('running', 'paused') AND deleted_at IS NULL AND owner_device_id IS NOT NULL",
    );
    await customStatement(
      "CREATE INDEX IF NOT EXISTS idx_timer_owner_state ON timer_sessions (owner_device_id, state, updated_at) WHERE deleted_at IS NULL",
    );
  }

  Future<void> _createFts() async {
    // Recreate the v6 object so databases created during the partial v6
    // remediation cannot retain the old, non-external-content shape.
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_insert');
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_update');
    await customStatement('DROP TRIGGER IF EXISTS tasks_fts_delete');
    await customStatement('DROP TABLE IF EXISTS tasks_fts');
    await customStatement(
      'CREATE VIRTUAL TABLE tasks_fts USING fts5('
      'title, description, notes, content=tasks, content_rowid=rowid)',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks '
      'WHEN NEW.deleted_at IS NULL BEGIN '
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "VALUES (NEW.rowid, NEW.title, COALESCE(NEW.description, ''), COALESCE(NEW.notes, '')); END",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_update '
      'AFTER UPDATE OF title, description, notes, deleted_at ON tasks BEGIN '
      "INSERT INTO tasks_fts(tasks_fts, rowid, title, description, notes) "
      "SELECT 'delete', OLD.rowid, OLD.title, COALESCE(OLD.description, ''), COALESCE(OLD.notes, '') "
      'WHERE OLD.deleted_at IS NULL; '
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "SELECT NEW.rowid, NEW.title, COALESCE(NEW.description, ''), COALESCE(NEW.notes, '') "
      'WHERE NEW.deleted_at IS NULL; END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER DELETE ON tasks '
      'WHEN OLD.deleted_at IS NULL BEGIN '
      "INSERT INTO tasks_fts(tasks_fts, rowid, title, description, notes) "
      "VALUES ('delete', OLD.rowid, OLD.title, COALESCE(OLD.description, ''), COALESCE(OLD.notes, '')); END",
    );
    await customStatement(
      'INSERT INTO tasks_fts(rowid, title, description, notes) '
      "SELECT rowid, title, COALESCE(description, ''), COALESCE(notes, '') "
      'FROM tasks WHERE deleted_at IS NULL',
    );
  }

  Future<void> _createSyncIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_log_pending '
      'ON sync_log(state, next_attempt_at, created_at) '
      "WHERE state IN ('pending', 'error')",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_record '
      'ON sync_conflicts(table_name, record_id, created_at)',
    );
  }

  /// Database triggers cover every local mutation path, including aggregate
  /// commands that write more than one domain table. The marker is set by
  /// SyncDao for remote apply, so pulled rows never echo into the outbox.
  Future<void> _createSyncTriggers() async {
    // CREATE TRIGGER IF NOT EXISTS cannot replace a previously installed
    // body. The source/cache split therefore recreates these known triggers.
    await _dropSyncTriggers();
    const guard =
        "NOT EXISTS (SELECT 1 FROM app_settings WHERE key = 'sync.apply_mode' AND value = '1')";
    const operationId =
        "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))";
    const now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

    Future<void> createForTable({
      required String table,
      required String tableName,
      required String primaryKeyNew,
      required String primaryKeyOld,
      required String recordIdNew,
      required String recordIdOld,
      required String jsonNew,
      required String jsonOld,
      required String updateColumns,
      String deleteOperationWhen =
          'NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL',
    }) async {
      final payloadJson =
          "json_set(json_set($jsonNew, '\$._planner_payload_version', 2), "
          "'\$._planner_revision', NEW.revision)";
      final tombstoneJson =
          "json_set(json_set($jsonOld, '\$._planner_payload_version', 2), "
          "'\$._planner_revision', OLD.revision)";
      await customStatement('''
CREATE TRIGGER IF NOT EXISTS sync_${table}_insert
AFTER INSERT ON $table
WHEN $guard
BEGIN
  UPDATE $table SET sync_status = 1 WHERE $primaryKeyNew;
  INSERT INTO sync_log(
    operation_id, table_name, record_id, operation, expected_server_version,
    payload, state, attempt_count, created_at, updated_at
  ) VALUES (
    $operationId, '$tableName', $recordIdNew, 'insert', NEW.server_version,
    $payloadJson, 'pending', 0, $now, $now
  );
END;
''');
      await customStatement('''
CREATE TRIGGER IF NOT EXISTS sync_${table}_update
AFTER UPDATE OF $updateColumns ON $table
WHEN $guard
BEGIN
  UPDATE $table
  SET sync_status = 1,
      revision = CASE WHEN revision > OLD.revision THEN revision ELSE OLD.revision + 1 END
  WHERE $primaryKeyNew;
  INSERT INTO sync_log(
    operation_id, table_name, record_id, operation, expected_server_version,
    payload, state, attempt_count, created_at, updated_at
  ) VALUES (
    $operationId, '$tableName', $recordIdNew,
    CASE WHEN $deleteOperationWhen
      THEN 'delete' ELSE 'update' END,
    NEW.server_version, $payloadJson, 'pending', 0, $now, $now
  );
END;
''');
      await customStatement('''
CREATE TRIGGER IF NOT EXISTS sync_${table}_delete
AFTER DELETE ON $table
WHEN $guard
BEGIN
  INSERT INTO sync_log(
    operation_id, table_name, record_id, operation, expected_server_version,
    payload, state, attempt_count, created_at, updated_at
  ) VALUES (
    $operationId, '$tableName', $recordIdOld, 'delete', OLD.server_version,
    $tombstoneJson, 'pending', 0, $now, $now
  );
END;
''');
    }

    await createForTable(
      table: 'tasks',
      tableName: 'tasks',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      // estimated_duration_min is a compatibility projection. Updating it
      // alone must not create a semantic sync operation.
      updateColumns: 'id, title, description, start_time, end_time, manual_duration_adjustment_min, manual_actual_set, category_id, priority, status, notes, recurring_rule_id, recurrence_removal_reason, rescheduled_from_id, rescheduled_to_id, is_inbox, inbox_content_version, due_date, missed_at, plan_title_history_json, display_plan_change_id, created_at, updated_at, deleted_at',
      // Rule-exclusion tombstones need their full payload on the server.
      deleteOperationWhen: 'NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL AND NEW.recurrence_removal_reason IS NULL',
      jsonNew: "json_object('id', NEW.id, 'title', NEW.title, 'description', NEW.description, 'start_time', NEW.start_time, 'end_time', NEW.end_time, 'estimated_duration_min', NEW.estimated_duration_min, 'actual_duration_min', NEW.actual_duration_min, 'manual_duration_adjustment_min', NEW.manual_duration_adjustment_min, 'manual_actual_set', NEW.manual_actual_set, 'category_id', NEW.category_id, 'priority', NEW.priority, 'status', NEW.status, 'notes', NEW.notes, 'recurring_rule_id', NEW.recurring_rule_id, 'recurrence_removal_reason', NEW.recurrence_removal_reason, 'rescheduled_from_id', NEW.rescheduled_from_id, 'rescheduled_to_id', NEW.rescheduled_to_id, 'is_inbox', NEW.is_inbox, 'inbox_content_version', NEW.inbox_content_version, 'due_date', NEW.due_date, 'missed_at', NEW.missed_at, 'plan_title_history_json', NEW.plan_title_history_json, 'display_plan_change_id', NEW.display_plan_change_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'categories',
      tableName: 'categories',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, name, color_hex, sort_order, is_focus, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'name', NEW.name, 'color_hex', NEW.color_hex, 'sort_order', NEW.sort_order, 'is_focus', NEW.is_focus, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'subtasks',
      tableName: 'subtasks',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, task_id, title, is_completed, sort_order, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'task_id', NEW.task_id, 'title', NEW.title, 'is_completed', NEW.is_completed, 'sort_order', NEW.sort_order, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'task_id', OLD.task_id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'tags',
      tableName: 'tags',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, name, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'name', NEW.name, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'task_tags',
      tableName: 'task_tags',
      primaryKeyNew: 'task_id = NEW.task_id AND tag_id = NEW.tag_id',
      primaryKeyOld: 'task_id = OLD.task_id AND tag_id = OLD.tag_id',
      recordIdNew: "NEW.task_id || ':' || NEW.tag_id",
      recordIdOld: "OLD.task_id || ':' || OLD.tag_id",
      updateColumns: 'task_id, tag_id, created_at, updated_at, deleted_at',
      jsonNew: "json_object('task_id', NEW.task_id, 'tag_id', NEW.tag_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('task_id', OLD.task_id, 'tag_id', OLD.tag_id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'recurring_rules',
      tableName: 'recurring_rules',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, rrule, task_title, task_description, duration_min, category_id, priority, tags_json, start_time_of_day, start_date, end_date, is_active, exceptions_json, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'rrule', NEW.rrule, 'task_title', NEW.task_title, 'task_description', NEW.task_description, 'duration_min', NEW.duration_min, 'category_id', NEW.category_id, 'priority', NEW.priority, 'tags_json', NEW.tags_json, 'start_time_of_day', NEW.start_time_of_day, 'start_date', NEW.start_date, 'end_date', NEW.end_date, 'is_active', NEW.is_active, 'exceptions_json', NEW.exceptions_json, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'task_templates',
      tableName: 'task_templates',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, name, description, duration_min, category_id, priority, tags_json, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'name', NEW.name, 'description', NEW.description, 'duration_min', NEW.duration_min, 'category_id', NEW.category_id, 'priority', NEW.priority, 'tags_json', NEW.tags_json, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'daily_reviews',
      tableName: 'daily_reviews',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, date, reflection, energy_level, productivity_rating, planning_accuracy_rating, wins_json, improvements_json, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'date', NEW.date, 'reflection', NEW.reflection, 'energy_level', NEW.energy_level, 'productivity_rating', NEW.productivity_rating, 'planning_accuracy_rating', NEW.planning_accuracy_rating, 'wins_json', NEW.wins_json, 'improvements_json', NEW.improvements_json, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'date', OLD.date, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'weekly_reviews',
      tableName: 'weekly_reviews',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, week_start_date, reflection, overall_rating, goals_met_json, goals_missed_json, next_week_focus_json, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'week_start_date', NEW.week_start_date, 'reflection', NEW.reflection, 'overall_rating', NEW.overall_rating, 'goals_met_json', NEW.goals_met_json, 'goals_missed_json', NEW.goals_missed_json, 'next_week_focus_json', NEW.next_week_focus_json, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'week_start_date', OLD.week_start_date, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'timer_sessions',
      tableName: 'timer_sessions',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns: 'id, task_id, started_at, ended_at, duration_sec, state, running_since, work_intervals_json, owner_device_id, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'task_id', NEW.task_id, 'started_at', NEW.started_at, 'ended_at', NEW.ended_at, 'duration_sec', NEW.duration_sec, 'state', NEW.state, 'running_since', NEW.running_since, 'work_intervals_json', NEW.work_intervals_json, 'owner_device_id', NEW.owner_device_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'task_id', OLD.task_id, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
    await createForTable(
      table: 'day_contexts',
      tableName: 'day_contexts',
      primaryKeyNew: 'id = NEW.id',
      primaryKeyOld: 'id = OLD.id',
      recordIdNew: 'NEW.id',
      recordIdOld: 'OLD.id',
      updateColumns:
          'id, date, kind, custom_label, created_at, updated_at, deleted_at',
      jsonNew: "json_object('id', NEW.id, 'date', NEW.date, 'kind', NEW.kind, 'custom_label', NEW.custom_label, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'deleted_at', NEW.deleted_at, 'server_version', NEW.server_version)",
      jsonOld:
          "json_object('id', OLD.id, 'date', OLD.date, 'kind', OLD.kind, 'custom_label', OLD.custom_label, 'created_at', OLD.created_at, 'updated_at', OLD.updated_at, 'deleted_at', $now, 'server_version', OLD.server_version)",
    );
  }

  Future<void> _ensureDayContextTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS day_contexts (
        id TEXT NOT NULL PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        custom_label TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 1,
        server_version INTEGER NULL,
        CHECK (length(date) = 10 AND date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(date) = date),
        CHECK (kind IN ('office', 'holiday', 'leave', 'travel', 'custom')),
        CHECK ((kind = 'custom' AND custom_label IS NOT NULL AND length(trim(custom_label)) BETWEEN 1 AND 80) OR (kind <> 'custom' AND custom_label IS NULL))
      )
    ''');
  }

  /// Development builds used the v8 number while the coordinated Foundation
  /// was still being completed. Repair any partial v8 shape in place without
  /// a reset or schema relabel.
  Future<void> _ensureTimeAccountingSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS planner_migration_recovery (
        recovery_id TEXT NOT NULL PRIMARY KEY,
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        reason TEXT NOT NULL,
        recovered_at TEXT NOT NULL
      )
    ''');
    final taskColumns = await customSelect('PRAGMA table_info(tasks)').get();
    final timerColumns = await customSelect('PRAGMA table_info(timer_sessions)')
        .get();
    final taskNames = taskColumns
        .map((row) => row.read<String>('name'))
        .toSet();
    final timerNames = timerColumns
        .map((row) => row.read<String>('name'))
        .toSet();
    if (!taskNames.contains('manual_actual_set')) {
      await customStatement(
        'ALTER TABLE tasks ADD COLUMN manual_actual_set INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!taskNames.contains('plan_title_history_json')) {
      await customStatement(
        "ALTER TABLE tasks ADD COLUMN plan_title_history_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (!taskNames.contains('display_plan_change_id')) {
      await customStatement(
        'ALTER TABLE tasks ADD COLUMN display_plan_change_id TEXT',
      );
    }
    if (!timerNames.contains('state')) {
      await customStatement(
        "ALTER TABLE timer_sessions ADD COLUMN state TEXT NOT NULL DEFAULT 'finished'",
      );
    }
    if (!timerNames.contains('running_since')) {
      await customStatement(
        'ALTER TABLE timer_sessions ADD COLUMN running_since TEXT',
      );
    }
    if (!timerNames.contains('work_intervals_json')) {
      await customStatement(
        "ALTER TABLE timer_sessions ADD COLUMN work_intervals_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (!timerNames.contains('owner_device_id')) {
      await customStatement(
        'ALTER TABLE timer_sessions ADD COLUMN owner_device_id TEXT',
      );
    }

    final previousApplyMode = await customSelect(
      "SELECT value FROM app_settings WHERE key = 'sync.apply_mode'",
    ).getSingleOrNull();
    await customStatement(
      "INSERT OR REPLACE INTO app_settings(key, value) VALUES ('sync.apply_mode', '1')",
    );
    try {
      final anomalousOpen = await customSelect(
        "SELECT id, task_id, started_at, duration_sec FROM timer_sessions WHERE ended_at IS NULL AND duration_sec > 0 AND deleted_at IS NULL",
      ).get();
      for (final row in anomalousOpen) {
        final id = row.read<String>('id');
        await customStatement(
          'INSERT OR IGNORE INTO planner_migration_recovery '
          '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            'v8:timer_sessions:$id',
            'timer_sessions',
            id,
            jsonEncode(row.data),
            'Open legacy timer retained unclaimed; nonzero duration excluded from Actual Duration',
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
      // Preserve every legacy row/ID. Finished rows retain their recorded
      // duration; open rows become unclaimed running sessions, never silently
      // finalized or counted.
      await customStatement(
        "UPDATE timer_sessions SET state = 'finished', running_since = NULL, work_intervals_json = COALESCE(work_intervals_json, '[]') WHERE ended_at IS NOT NULL AND (state IS NULL OR state <> 'finished' OR running_since IS NOT NULL)",
      );
      await customStatement(
        "UPDATE timer_sessions SET state = 'running', running_since = COALESCE(running_since, started_at), work_intervals_json = COALESCE(work_intervals_json, '[]'), owner_device_id = NULL WHERE ended_at IS NULL AND (state IS NULL OR state = 'finished')",
      );

      // Cache refresh stays non-semantic under the sync guard and happens
      // after every timer source row has its migrated state.
      await customStatement('''
        UPDATE tasks
        SET actual_duration_min = CASE
          WHEN manual_actual_set = 0 THEN actual_duration_min
          ELSE MAX(0, manual_duration_adjustment_min + COALESCE((
            SELECT SUM(s.duration_sec) / 60 FROM timer_sessions s
            WHERE s.task_id = tasks.id AND s.state = 'finished'
              AND s.ended_at IS NOT NULL AND s.deleted_at IS NULL
          ), 0))
        END
      ''');
      // Queue one canonical post-transform snapshot after Inbox conversion,
      // timer-state migration, manual-source inference and cache rebuild have
      // all completed. The recovery ledger is durable across a process stop;
      // the deterministic operation ID makes reopening retry-safe.
      final reconciliationTasks = await customSelect(
        "SELECT DISTINCT row_id FROM planner_migration_recovery "
        "WHERE table_name = 'tasks' AND ("
        "reason LIKE 'Migrated legacy explicit Inbox content%' OR "
        "reason LIKE 'Inferred one-time manual actual source%')",
      ).get();
      for (final row in reconciliationTasks) {
        await _enqueueV8TaskReconciliation(row.read<String>('row_id'));
      }
    } finally {
      if (previousApplyMode == null) {
        await customStatement(
          "DELETE FROM app_settings WHERE key = 'sync.apply_mode'",
        );
      } else {
        await customStatement(
          "UPDATE app_settings SET value = ? WHERE key = 'sync.apply_mode'",
          [previousApplyMode.read<String>('value')],
        );
      }
    }
  }
}
