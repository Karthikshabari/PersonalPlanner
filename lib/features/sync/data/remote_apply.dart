import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/acyclic_links.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../../core/utils/missed_at.dart';
import '../../task_editor/domain/plan_title_history.dart';
import '../domain/sync_models.dart';
import '../domain/sync_validation.dart';

/// Applies one server feed row to SQLite without producing an outbound echo.
/// Parent/child ordering is handled by [SyncRepository] before this class is
/// called. Every operation is an upsert of the complete server snapshot;
/// deletes remain local tombstones.
class SyncRemoteApplier {
  SyncRemoteApplier(this._db);

  final AppDatabase _db;

  Future<void> validate(
    SyncRemoteChange change, {
    bool checkMaterializedState = true,
    bool checkHistoryLinks = true,
  }) async {
    await _normalizeLegacyTaskPayload(change);
    await _normalizeLegacyTimerPayload(change);
    SyncPayloadValidator.validate(change);
    if (change.operation == 'delete') return;
    if (change.tableName == 'tasks') {
      final current = await _db.taskDao.getTaskById(change.recordId);
      if (current != null) {
        PlanTitleHistory.validateTransition(
          previous: PlanTitleHistory.decodeJson(current.planTitleHistoryJson),
          next: PlanTitleHistory.decodeJson(
            change.payload['plan_title_history_json'] as String,
          ),
        );
      }
    }
    if (checkMaterializedState &&
        change.tableName == 'timer_sessions' &&
        change.payload['state'] == 'running' &&
        change.payload['owner_device_id'] != null) {
      final ownerDeviceId = change.payload['owner_device_id'].toString();
      final active =
          await (_db.select(_db.timerSessions)..where(
                (session) =>
                    session.state.equals('running') &
                    session.ownerDeviceId.equals(ownerDeviceId) &
                    session.deletedAt.isNull(),
              ))
              .get();
      if (active.any((session) => session.id != change.recordId)) {
        throw const SyncValidationException(
          'Remote running timer conflicts with this device owner',
        );
      }
    }
    if (checkHistoryLinks && change.tableName == 'tasks') {
      final graph = await _loadHistoryGraph();
      _stageTaskHistoryChange(graph, change);
      _validateHistoryGraph(graph);
    }
  }

  /// Validates a coalesced pull page with one relationship-graph read and
  /// traversal. Payload/schema checks still run for each change. A caller can
  /// fall back to [validate] per change if this final staged graph is invalid,
  /// preserving quarantine granularity for malformed pages.
  Future<void> validateBatch(
    Iterable<SyncRemoteChange> source, {
    bool checkMaterializedState = true,
  }) async {
    final changes = source.toList(growable: false);
    for (final change in changes) {
      await validate(
        change,
        checkMaterializedState: checkMaterializedState,
        checkHistoryLinks: false,
      );
    }
    final taskChanges = <String, SyncRemoteChange>{
      for (final change in changes)
        if (change.tableName == 'tasks') change.recordId: change,
    };
    if (taskChanges.isEmpty) return;
    final graph = await _loadHistoryGraph();
    for (final change in taskChanges.values) {
      _stageTaskHistoryChange(graph, change);
    }
    _validateHistoryGraph(graph);
  }

  Future<Map<String, Set<String>>> _loadHistoryGraph() async {
    final rows = await (_db.select(_db.tasks)).get();
    final graph = <String, Set<String>>{
      for (final row in rows) row.id: <String>{},
    };
    for (final row in rows) {
      if (row.rescheduledToId != null) {
        graph[row.id]!.add(row.rescheduledToId!);
      }
      if (row.rescheduledFromId != null) {
        graph.putIfAbsent(row.rescheduledFromId!, () => <String>{}).add(row.id);
      }
    }
    return graph;
  }

  static void _stageTaskHistoryChange(
    Map<String, Set<String>> graph,
    SyncRemoteChange change,
  ) {
    // A compact tombstone may contain only the primary key and deleted_at.
    // It does not describe relationship fields, so keep the existing edges
    // while validating the staged page instead of hiding a pre-existing cycle.
    if (change.operation == 'delete' &&
        !change.payload.containsKey('rescheduled_from_id') &&
        !change.payload.containsKey('rescheduled_to_id')) {
      return;
    }
    graph[change.recordId] = <String>{};
    final from = change.payload['rescheduled_from_id']?.toString();
    final to = change.payload['rescheduled_to_id']?.toString();
    if (to != null && to.isNotEmpty) graph[change.recordId]!.add(to);
    if (from != null && from.isNotEmpty) {
      graph.putIfAbsent(from, () => <String>{}).add(change.recordId);
    }
  }

  static void _validateHistoryGraph(Map<String, Set<String>> graph) {
    try {
      validateAcyclicLinks(graph);
    } on StateError catch (error) {
      throw SyncValidationException(error.message);
    }
  }

  Future<void> apply(
    SyncRemoteChange change, {
    bool checkHistoryLinks = true,
  }) async {
    await validate(change, checkHistoryLinks: checkHistoryLinks);
    final definition = _definitions[change.tableName];
    if (definition == null) {
      throw StateError('Unsupported sync table: ${change.tableName}');
    }
    // A conflict can report that the server row has already disappeared.
    // There is no complete row to insert in that case, so retain the local
    // relationship/record as a tombstone instead of writing nulls into
    // required columns.
    if (change.operation == 'delete') {
      if (_hasCompleteSnapshot(change, definition)) {
        final snapshot = Map<String, dynamic>.from(change.payload)
          ..remove('deleted')
          ..['deleted_at'] =
              change.payload['deleted_at'] ??
              DateTime.now().toUtc().toIso8601String();
        if (change.tableName == 'tasks') {
          snapshot['recurrence_removal_reason'] = null;
        }
        final snapshotChange = SyncRemoteChange(
          changeId: change.changeId,
          operationId: change.operationId,
          tableName: change.tableName,
          recordId: change.recordId,
          operation: 'update',
          serverVersion: change.serverVersion,
          serverTimestamp: change.serverTimestamp,
          payload: snapshot,
        );
        await validate(snapshotChange);
        await _applySnapshot(snapshotChange, definition);
      } else {
        await _applyMissingTombstone(change, definition);
      }
      return;
    }
    await _applySnapshot(change, definition);
  }

  bool _hasCompleteSnapshot(
    SyncRemoteChange change,
    _SyncTableDefinition definition,
  ) {
    if (change.tableName == 'task_tags') {
      return definition.columns.every(
        (column) => change.payload.containsKey(column.jsonKey),
      );
    }
    if (change.payload['id']?.toString() != change.recordId) return false;
    final complete = definition.columns.every(
      (column) => change.payload.containsKey(column.jsonKey),
    );
    if (complete) return true;
    // A pre-v8 Task snapshot is still a complete semantic row. The adapter
    // fills the new marker/due fields before the SQL upsert, so it must not be
    // misclassified as a compact tombstone.
    if (change.tableName == 'tasks') {
      return definition.columns
          .where(
            (column) =>
                column.jsonKey != 'inbox_content_version' &&
                column.jsonKey != 'due_date' &&
                column.jsonKey != 'manual_actual_set' &&
                column.jsonKey != 'plan_title_history_json' &&
                column.jsonKey != 'display_plan_change_id' &&
                column.jsonKey != 'recurrence_removal_reason',
          )
          .every((column) => change.payload.containsKey(column.jsonKey));
    }
    return false;
  }

  Future<void> _normalizeLegacyTaskPayload(SyncRemoteChange change) async {
    if (change.tableName != 'tasks' || change.operation == 'delete') return;
    final payload = change.payload;
    final current = await _db.taskDao.getTaskById(change.recordId);
    final isInbox =
        payload['is_inbox'] == true ||
        payload['is_inbox'] == 1 ||
        payload['is_inbox'] == '1';
    if (!payload.containsKey('inbox_content_version')) {
      if (isInbox) {
        final currentContent = current?.inboxContentVersion == 1
            ? current?.description
            : null;
        final rawDescription = payload['description'];
        if ((rawDescription == null || rawDescription == '') &&
            currentContent != null) {
          payload['description'] = currentContent;
        } else if (rawDescription == null || rawDescription == '') {
          payload['description'] = payload['title']?.toString() ?? '';
        } else if (rawDescription != payload['title']) {
          payload['description'] =
              '${payload['title'] ?? ''}\n\n$rawDescription';
        }
        payload['inbox_content_version'] = 1;
      } else {
        payload['inbox_content_version'] = 0;
      }
    }
    // A legacy update did not carry due_date. Preserve a locally-created due
    // date instead of interpreting absence as an explicit clear.
    if (!payload.containsKey('due_date')) {
      payload['due_date'] = current?.dueDate;
    }
    if (!payload.containsKey('plan_title_history_json')) {
      payload['plan_title_history_json'] =
          current?.planTitleHistoryJson ?? '[]';
    }
    if (!payload.containsKey('display_plan_change_id')) {
      payload['display_plan_change_id'] = current?.displayPlanChangeId;
    }
    if (!payload.containsKey('recurrence_removal_reason')) {
      payload['recurrence_removal_reason'] = current?.recurrenceRemovalReason;
    }
  }

  Future<void> _normalizeLegacyTimerPayload(SyncRemoteChange change) async {
    if (change.tableName != 'timer_sessions' || change.operation == 'delete') {
      return;
    }
    final payload = change.payload;
    if (payload.containsKey('state')) return;
    final current = await _db.timerDao.getSessionById(change.recordId);
    // Historical active snapshots do not contain a state/interval body. If a
    // newer v2 local row is already materialized, preserve its precision
    // rather than reverting it to a synthetic legacy running row.
    if (payload['ended_at'] == null &&
        current != null &&
        current.deletedAt == null &&
        current.state != 'finished') {
      payload['state'] = current.state;
      payload['running_since'] = current.runningSince?.toIso8601String();
      payload['work_intervals_json'] = current.workIntervalsJson;
      payload['owner_device_id'] = current.ownerDeviceId;
    }
  }

  Future<void> _applySnapshot(
    SyncRemoteChange change,
    _SyncTableDefinition definition,
  ) async {
    final normalized = _canonicalizeInstants(change.tableName, change.payload);
    final payload = jsonEncode(normalized);
    final jsonExpressions = [
      for (final column in definition.columns)
        "json_extract(?, '\$.${column.jsonKey}')",
    ];
    final variables = <Object>[
      for (var i = 0; i < definition.columns.length; i++) payload,
      change.serverVersion,
    ];
    final insertColumns = [
      ...definition.columns.map((column) => column.sqlName),
      'server_version',
      'sync_status',
      'revision',
    ].join(', ');
    final insertValues = [...jsonExpressions, '?', '0', '1'].join(', ');
    final semanticColumns = definition.columns
        .skip(1)
        .where(
          (column) => !definition.nonSemanticColumns.contains(column.sqlName),
        )
        .toList(growable: false);
    final semanticChanged = semanticColumns
        .map(
          (column) =>
              'excluded.${column.sqlName} IS NOT ${definition.tableName}.${column.sqlName}',
        )
        .join(' OR ');
    final updates = [
      for (final column in definition.columns.skip(1))
        '${column.sqlName} = ${definition.preserveOnUpdateColumns.contains(column.sqlName) ? '${definition.tableName}.${column.sqlName}' : 'excluded.${column.sqlName}'}',
      'server_version = excluded.server_version',
      'sync_status = 0',
      'revision = CASE WHEN $semanticChanged THEN '
          '${definition.tableName}.revision + 1 ELSE '
          '${definition.tableName}.revision END',
    ].join(', ');
    final sql =
        '''
INSERT INTO ${definition.tableName}($insertColumns)
VALUES ($insertValues)
ON CONFLICT(${definition.primaryKey}) DO UPDATE SET $updates
''';
    await _db.customStatement(sql, variables);
  }

  static Map<String, dynamic> _canonicalizeInstants(
    String table,
    Map<String, dynamic> source,
  ) {
    const fields = {
      'tasks': {
        'start_time',
        'end_time',
        'missed_at',
        'created_at',
        'updated_at',
        'deleted_at',
      },
      'categories': {'created_at', 'updated_at', 'deleted_at'},
      'subtasks': {'created_at', 'updated_at', 'deleted_at'},
      'tags': {'created_at', 'updated_at', 'deleted_at'},
      'task_tags': {'created_at', 'updated_at', 'deleted_at'},
      'recurring_rules': {'created_at', 'updated_at', 'deleted_at'},
      'task_templates': {'created_at', 'updated_at', 'deleted_at'},
      'daily_reviews': {'created_at', 'updated_at', 'deleted_at'},
      'weekly_reviews': {'created_at', 'updated_at', 'deleted_at'},
      'timer_sessions': {
        'started_at',
        'ended_at',
        'running_since',
        'created_at',
        'updated_at',
        'deleted_at',
      },
      'day_contexts': {'created_at', 'updated_at', 'deleted_at'},
    };
    final result = Map<String, dynamic>.from(source);
    for (final field in fields[table] ?? const <String>{}) {
      final value = result[field];
      if (value == null) continue;
      // missed_at is intentionally stored at minute precision (the inbox
      // badge and local stamping contract use YYYY-MM-DDTHH:mm).
      if (field == 'missed_at') {
        final canonical = MissedAtCodec.normalize(value.toString());
        if (canonical != null) result[field] = canonical;
      } else {
        final parsed = DateTime.tryParse(value.toString());
        if (parsed != null) {
          result[field] = parsed.toUtc().toIso8601String();
        }
      }
    }
    if (table == 'tasks') {
      final isInbox =
          result['is_inbox'] == true ||
          result['is_inbox'] == 1 ||
          result['is_inbox'] == '1';
      if (isInbox) {
        result['start_time'] = null;
        result['end_time'] = null;
      }
      final start = DateTime.tryParse(result['start_time']?.toString() ?? '');
      final end = DateTime.tryParse(result['end_time']?.toString() ?? '');
      result['estimated_duration_min'] = isInbox
          ? null
          : TaskTimeMetrics.plannedMinutes(start, end);
    }
    return result;
  }

  Future<void> _applyMissingTombstone(
    SyncRemoteChange change,
    _SyncTableDefinition definition,
  ) async {
    final deletedAt =
        change.payload['deleted_at'] ??
        DateTime.now().toUtc().toIso8601String();
    final variables = <Object>[deletedAt.toString(), change.serverVersion];
    final where = definition.primaryKey == 'task_id, tag_id'
        ? 'task_id = ? AND tag_id = ?'
        : 'id = ?';
    if (definition.primaryKey == 'task_id, tag_id') {
      final pieces = change.recordId.split(':');
      if (pieces.length != 2) throw StateError('Invalid task_tags record ID');
      variables.addAll([pieces[0], pieces[1]]);
    } else {
      variables.add(change.recordId);
    }
    final clearRecurrenceReason = change.tableName == 'tasks'
        ? 'recurrence_removal_reason = NULL, '
        : '';
    await _db.customStatement(
      'UPDATE ${definition.tableName} SET deleted_at = ?, '
      '$clearRecurrenceReason'
      'server_version = ?, sync_status = 0 WHERE $where',
      variables,
    );
  }
}

class _SyncTableDefinition {
  final String tableName;
  final String primaryKey;
  final List<_SyncColumn> columns;
  final Set<String> nonSemanticColumns;
  final Set<String> preserveOnUpdateColumns;

  const _SyncTableDefinition({
    required this.tableName,
    required this.primaryKey,
    required this.columns,
    this.nonSemanticColumns = const {},
    this.preserveOnUpdateColumns = const {},
  });
}

class _SyncColumn {
  final String sqlName;
  final String jsonKey;

  const _SyncColumn(this.sqlName, [String? jsonKey])
    : jsonKey = jsonKey ?? sqlName;
}

final _definitions = <String, _SyncTableDefinition>{
  'tasks': _SyncTableDefinition(
    tableName: 'tasks',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('title'),
      _SyncColumn('description'),
      _SyncColumn('start_time'),
      _SyncColumn('end_time'),
      _SyncColumn('estimated_duration_min'),
      _SyncColumn('actual_duration_min'),
      _SyncColumn('manual_duration_adjustment_min'),
      _SyncColumn('manual_actual_set'),
      _SyncColumn('category_id'),
      _SyncColumn('priority'),
      _SyncColumn('status'),
      _SyncColumn('notes'),
      _SyncColumn('recurring_rule_id'),
      _SyncColumn('recurrence_removal_reason'),
      _SyncColumn('rescheduled_from_id'),
      _SyncColumn('rescheduled_to_id'),
      _SyncColumn('is_inbox'),
      _SyncColumn('inbox_content_version'),
      _SyncColumn('due_date'),
      _SyncColumn('missed_at'),
      _SyncColumn('plan_title_history_json'),
      _SyncColumn('display_plan_change_id'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
    nonSemanticColumns: const {'actual_duration_min', 'estimated_duration_min'},
    preserveOnUpdateColumns: const {'actual_duration_min'},
  ),
  'categories': _SyncTableDefinition(
    tableName: 'categories',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('name'),
      _SyncColumn('color_hex'),
      _SyncColumn('sort_order'),
      _SyncColumn('is_focus'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'subtasks': _SyncTableDefinition(
    tableName: 'subtasks',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('task_id'),
      _SyncColumn('title'),
      _SyncColumn('is_completed'),
      _SyncColumn('sort_order'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'tags': _SyncTableDefinition(
    tableName: 'tags',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('name'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'task_tags': _SyncTableDefinition(
    tableName: 'task_tags',
    primaryKey: 'task_id, tag_id',
    columns: [
      _SyncColumn('task_id'),
      _SyncColumn('tag_id'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'recurring_rules': _SyncTableDefinition(
    tableName: 'recurring_rules',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('rrule'),
      _SyncColumn('task_title'),
      _SyncColumn('task_description'),
      _SyncColumn('duration_min'),
      _SyncColumn('category_id'),
      _SyncColumn('priority'),
      _SyncColumn('tags_json'),
      _SyncColumn('start_time_of_day'),
      _SyncColumn('start_date'),
      _SyncColumn('end_date'),
      _SyncColumn('is_active'),
      _SyncColumn('exceptions_json'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'task_templates': _SyncTableDefinition(
    tableName: 'task_templates',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('name'),
      _SyncColumn('description'),
      _SyncColumn('duration_min'),
      _SyncColumn('category_id'),
      _SyncColumn('priority'),
      _SyncColumn('tags_json'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'daily_reviews': _SyncTableDefinition(
    tableName: 'daily_reviews',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('date'),
      _SyncColumn('reflection'),
      _SyncColumn('energy_level'),
      _SyncColumn('productivity_rating'),
      _SyncColumn('planning_accuracy_rating'),
      _SyncColumn('wins_json'),
      _SyncColumn('improvements_json'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'weekly_reviews': _SyncTableDefinition(
    tableName: 'weekly_reviews',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('week_start_date'),
      _SyncColumn('reflection'),
      _SyncColumn('overall_rating'),
      _SyncColumn('goals_met_json'),
      _SyncColumn('goals_missed_json'),
      _SyncColumn('next_week_focus_json'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'timer_sessions': _SyncTableDefinition(
    tableName: 'timer_sessions',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('task_id'),
      _SyncColumn('started_at'),
      _SyncColumn('ended_at'),
      _SyncColumn('duration_sec'),
      _SyncColumn('state'),
      _SyncColumn('running_since'),
      _SyncColumn('work_intervals_json'),
      _SyncColumn('owner_device_id'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
  'day_contexts': _SyncTableDefinition(
    tableName: 'day_contexts',
    primaryKey: 'id',
    columns: [
      _SyncColumn('id'),
      _SyncColumn('date'),
      _SyncColumn('kind'),
      _SyncColumn('custom_label'),
      _SyncColumn('created_at'),
      _SyncColumn('updated_at'),
      _SyncColumn('deleted_at'),
    ],
  ),
};
