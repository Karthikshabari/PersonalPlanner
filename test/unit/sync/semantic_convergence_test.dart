import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('semantic convergence (DB-004/014/015)', () {
    late AppDatabase db;
    late _ScriptedGateway gateway;
    late SyncRepository sync;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      gateway = _ScriptedGateway();
      sync = SyncRepository.withGateway(db, gateway, 'account');
    });

    tearDown(() => db.close());

    Future<Task> insertLocalTask() => TaskRepository(db).insertTask(
      Task(
        id: '',
        title: 'Deterministic task',
        startTime: DateTime.utc(2026, 1, 5, 9),
        endTime: DateTime.utc(2026, 1, 5, 10),
        status: TaskStatus.planned,
        createdAt: DateTime.utc(2026, 1, 5, 8),
        updatedAt: DateTime.utc(2026, 1, 5, 8),
      ),
    );

    test('insert of existing record with equal content is acknowledged, not '
        'surfaced as a conflict', () async {
      final task = await insertLocalTask();
      gateway.onApply = (table, recordId, payload) =>
          _conflictResponse(_remoteOf(payload), serverVersion: 7);

      expect(await sync.push(), isNull);

      final ops = await _allOps(db, 'tasks', task.id);
      expect(ops, isNotEmpty);
      expect(ops.map((op) => op.state), everyElement('acknowledged'));
      expect(await db.select(db.syncConflicts).get(), isEmpty);
      expect((await db.taskDao.getTaskById(task.id))!.serverVersion, 7);
    });

    test(
      'insert of existing record with a different title stays a conflict',
      () async {
        final task = await insertLocalTask();
        gateway.onApply = (table, recordId, payload) => _conflictResponse(
          _remoteOf(payload)..['title'] = 'Another device title',
          serverVersion: 7,
        );

        await sync.push();

        final conflicts = await db.select(db.syncConflicts).get();
        expect(conflicts, hasLength(1));
        final ops = await _allOps(db, 'tasks', task.id);
        expect(ops.map((op) => op.state), contains('conflict'));
      },
    );

    test('pulled insert equal to a pending local insert retires the local '
        'operation', () async {
      final task = await insertLocalTask();
      final pending = await db.syncDao.getActiveOperationsForRecord(
        'tasks',
        task.id,
      );
      expect(pending, hasLength(1));
      final remote = _remoteOf(jsonDecode(pending.single.payload) as Map)
        ..['title'] = 'Deterministic task';
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'remote-op-1',
          'table_name': 'tasks',
          'record_id': task.id,
          'operation': 'insert',
          'server_version': 3,
          'server_timestamp': DateTime.utc(2026, 1, 5, 12).toIso8601String(),
          'payload': remote,
        },
      ]);

      expect(await sync.pull(), isNull);

      final op = await db.syncDao.getOperation(pending.single.operationId);
      expect(op!.state, 'acknowledged');
      expect(await db.select(db.syncConflicts).get(), isEmpty);
      expect((await db.taskDao.getTaskById(task.id))!.serverVersion, 3);
    });

    test(
      'recurring occurrence materialized on two devices converges',
      () async {
        final day = DateTime(2026, 1, 5);
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-daily',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Daily standup',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: isoDateString(day),
                createdAt: DateTime.utc(2026, 1, 1),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            );
        expect(await RecurrenceService(db).materializeForDate(day), 1);
        gateway.onApply = (table, recordId, payload) {
          if (table != 'tasks') {
            return {
              'status': 'applied',
              'server_version': 1,
              'change_id': 1,
              'server_timestamp': DateTime.utc(2026, 1, 5).toIso8601String(),
            };
          }
          return _conflictResponse(_remoteOf(payload), serverVersion: 4);
        };

        expect(await sync.push(), isNull);

        expect(gateway.appliedTables, contains('tasks'));
        expect(await db.select(db.syncConflicts).get(), isEmpty);
      },
    );

    group('recurrence exception union', () {
      Future<(String conflictId, Map<String, dynamic> payload)> ruleConflict({
        required List<String> local,
        required List<String> remote,
        String ruleId = 'rule-conflict',
      }) async {
        final now = DateTime.utc(2026, 1, 1, 9);
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.recurringRules)
              .insert(
                RecurringRulesCompanion.insert(
                  id: ruleId,
                  rrule: 'FREQ=DAILY',
                  taskTitle: 'Daily standup',
                  durationMin: 30,
                  startTimeOfDay: '09:00',
                  startDate: '2026-01-01',
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
        });
        // Real local edits so the queued payload has the exact outbox shape.
        final repository = RecurringRepository(db);
        for (final date in local) {
          await repository.addException(ruleId, DateTime.parse(date));
        }
        final ops = await db.syncDao.getActiveOperationsForRecord(
          'recurring_rules',
          ruleId,
        );
        final newest = ops.last;
        final localPayload = jsonDecode(newest.payload) as Map<String, dynamic>;
        final remotePayload = _remoteOf(localPayload)
          ..['exceptions_json'] = jsonEncode(remote);
        await db.syncDao.markConflict(newest.operationId, now);
        await db.syncDao.insertConflict(
          SyncConflictsCompanion.insert(
            id: '$ruleId-card',
            operationId: newest.operationId,
            entityTableName: 'recurring_rules',
            recordId: ruleId,
            expectedServerVersion: const Value(5),
            actualServerVersion: const Value(6),
            localSnapshot: newest.payload,
            remoteSnapshot: jsonEncode(remotePayload),
            createdAt: now,
          ),
        );
        return ('$ruleId-card', remotePayload);
      }

      Future<List<SyncLogRow>> pendingRuleOps([
        String ruleId = 'rule-conflict',
      ]) async {
        final ops = await db.syncDao.getActiveOperationsForRecord(
          'recurring_rules',
          ruleId,
        );
        return ops.where((op) => op.state == 'pending').toList();
      }

      test('keep local unions recurrence exception dates', () async {
        final (conflictId, _) = await ruleConflict(
          local: ['2026-01-02'],
          remote: ['2026-01-03'],
        );

        await sync.keepLocal(conflictId);

        final pending = await pendingRuleOps();
        expect(pending, hasLength(1));
        final payload = jsonDecode(pending.single.payload) as Map;
        expect(payload['exceptions_json'], '["2026-01-02","2026-01-03"]');
      });

      test(
        'keep remote enqueues a follow-up only when local exceptions add dates',
        () async {
          final (supersetId, _) = await ruleConflict(
            local: ['2026-01-02'],
            remote: ['2026-01-02', '2026-01-03'],
          );
          await sync.keepRemote(supersetId);
          expect(await pendingRuleOps(), isEmpty);
          expect(await db.select(db.syncConflicts).get(), isEmpty);

          final (missingId, _) = await ruleConflict(
            local: ['2026-01-02'],
            remote: ['2026-01-03'],
            ruleId: 'rule-missing',
          );
          await sync.keepRemote(missingId);

          final pending = await pendingRuleOps('rule-missing');
          expect(pending, hasLength(1));
          final payload = jsonDecode(pending.single.payload) as Map;
          expect(payload['exceptions_json'], '["2026-01-02","2026-01-03"]');
        },
      );
    });
  });
}

Future<List<SyncLogRow>> _allOps(
  AppDatabase db,
  String table,
  String recordId,
) =>
    (db.select(db.syncLog)..where(
          (row) =>
              row.entityTableName.equals(table) & row.recordId.equals(recordId),
        ))
        .get();

/// A server-side copy of a client payload that only differs in bookkeeping.
Map<String, dynamic> _remoteOf(Map<dynamic, dynamic> clientPayload) {
  final remote = Map<String, dynamic>.from(clientPayload)
    ..removeWhere((key, _) => key.startsWith('_planner'))
    ..['created_at'] = DateTime.utc(2026, 1, 5, 7).toIso8601String()
    ..['updated_at'] = DateTime.utc(2026, 1, 5, 7, 30).toIso8601String();
  return remote;
}

Map<String, dynamic> _conflictResponse(
  Map<String, dynamic> remote, {
  required int serverVersion,
}) => {
  'status': 'conflict',
  'server_version': 0,
  'change_id': 0,
  'actual_server_version': serverVersion,
  'remote_snapshot': {...remote, 'server_version': serverVersion},
};

class _ScriptedGateway implements SyncRemoteGateway {
  @override
  Future<Object?> compactHistory() async => null;

  final appliedTables = <String>[];
  final pullPages = <List<Object?>>[];
  Object? Function(String table, String recordId, Map<String, dynamic> payload)?
  onApply;

  @override
  Future<Object?> getCapabilities() async => const {
    'protocol_version': 2,
    'payload_versions': [1, 2],
    'schedule_duration_projection': true,
    'inbox_content_version': true,
    'due_date': true,
    'plan_title_history': true,
    'manual_actual_source': true,
    'timer_state_machine': true,
    'day_contexts': true,
    'recurrence_removal_provenance': true,
  };

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) async {
    appliedTables.add(tableName);
    return onApply?.call(tableName, recordId, payload) ??
        {
          'status': 'applied',
          'server_version': 1,
          'change_id': 1,
          'server_timestamp': DateTime.utc(2026, 1, 5).toIso8601String(),
        };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => pullPages.isEmpty ? const <Object>[] : pullPages.removeAt(0);
}
