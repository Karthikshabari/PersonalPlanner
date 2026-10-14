import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';

import '../../helpers/sqlite_setup.dart';

/// UAT-003 leftover: operations an older build parked because a series was
/// ended at its first occurrence (end_date = start_date - 1 day).
void main() {
  setupSqliteForTests();

  const endBeforeStart =
      'Invalid sync data: Recurrence end_date must not precede start_date';

  late AppDatabase db;
  late SyncRepository repository;
  late _Gateway gateway;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gateway = _Gateway();
    repository = SyncRepository.withGateway(db, gateway, 'account');
  });

  tearDown(() => db.close());

  /// The rule as the device holds it: inactive, ending the day before it
  /// starts, already acknowledged at server version 171.
  Future<String> seedRule({String? id}) async {
    final ruleId = id ?? generateUuidV7();
    final created = DateTime.utc(2026, 9, 27, 9);
    await db.syncDao.runWithoutOutbound(() async {
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: ruleId,
              rrule: 'FREQ=DAILY',
              taskTitle: 'UAT-R',
              durationMin: 60,
              startTimeOfDay: '14:00',
              startDate: '2026-09-27',
              endDate: const Value('2026-09-26'),
              isActive: const Value(false),
              createdAt: created,
              updatedAt: created,
              serverVersion: const Value(171),
            ),
          );
    });
    return ruleId;
  }

  /// Queues an update carrying the invalid snapshot, as the trigger did.
  Future<String> queue(
    String ruleId, {
    required int isActive,
    String startTimeOfDay = '14:00',
  }) async {
    final operationId = generateUuidV7();
    await db.syncDao.enqueueOperation(
      SyncLogCompanion.insert(
        operationId: operationId,
        entityTableName: 'recurring_rules',
        recordId: ruleId,
        operation: 'update',
        expectedServerVersion: const Value(171),
        payload: jsonEncode({
          'id': ruleId,
          'rrule': 'FREQ=DAILY',
          'task_title': 'UAT-R',
          'task_description': null,
          'duration_min': 60,
          'category_id': null,
          'priority': 2,
          'tags_json': '[]',
          'start_time_of_day': startTimeOfDay,
          'start_date': '2026-09-27',
          'end_date': '2026-09-26',
          'is_active': isActive,
          'exceptions_json': '[]',
          'created_at': '2026-09-27T09:00:00.000Z',
          'updated_at': '2026-09-27T18:00:00.000Z',
          'deleted_at': null,
          'server_version': 171,
          '_planner_payload_version': 2,
        }),
        state: const Value('pending'),
        createdAt: DateTime.utc(2026, 9, 27, 18),
        updatedAt: DateTime.utc(2026, 9, 27, 18),
      ),
    );
    return operationId;
  }

  Future<void> park(String operationId, [String error = endBeforeStart]) =>
      db.syncDao.markPermanentError(
        operationId,
        now: DateTime.utc(2026, 10, 11, 18),
        error: error,
      );

  /// Device state: a parked active snapshot, then a pending inactive one.
  Future<(String, String, String)> seedDeviceState() async {
    final ruleId = await seedRule();
    final parked = await queue(ruleId, isActive: 1);
    final pending = await queue(ruleId, isActive: 0);
    await park(parked);
    return (ruleId, parked, pending);
  }

  Future<SyncLogRow> op(String id) async =>
      (await db.syncDao.getOperation(id))!;

  void expectValid(SyncLogRow row) {
    final payload = Map<String, dynamic>.from(jsonDecode(row.payload) as Map)
      ..remove('_planner_payload_version')
      ..remove('server_version');
    expect(
      () => SyncPayloadValidator.validate(
        SyncRemoteChange(
          changeId: 0,
          operationId: row.operationId,
          tableName: row.entityTableName,
          recordId: row.recordId,
          operation: row.operation,
          serverVersion: row.expectedServerVersion ?? 0,
          serverTimestamp: DateTime.utc(2026, 10, 13),
          payload: payload,
        ),
      ),
      returnsNormally,
    );
  }

  Future<List<SyncLogRow>> log() => db.select(db.syncLog).get();
  Future<List<RecurringRuleRow>> rules() => db.select(db.recurringRules).get();

  test('repairs the device state, is idempotent, and syncs', () async {
    final (ruleId, parkedId, pendingId) = await seedDeviceState();
    final otherRule = await seedRule();
    final otherOp = await queue(otherRule, isActive: 0);
    await park(otherOp, 'Invalid sync data: Invalid recurrence rule');
    final before = {for (final row in await log()) row.operationId: row};
    final otherRuleBefore = await db.recurringRuleDao.getRuleById(otherRule);

    await repository.repairRecurrenceEndDateOperations();

    for (final id in [parkedId, pendingId]) {
      final row = await op(id);
      expect(row.state, 'pending');
      expect(row.nextAttemptAt, isNull);
      expect(row.lastError, isNull);
      expect(row.seq, before[id]!.seq);
      expect(row.expectedServerVersion, 171);
      final payload = jsonDecode(row.payload) as Map;
      expect(payload['end_date'], '2026-09-27');
      // Never active on the server between the two pushes.
      expect(payload['is_active'], 0);
      expectValid(row);
    }
    expect(
      (await db.recurringRuleDao.getRuleById(ruleId))!.endDate,
      '2026-09-27',
    );
    // The local fix queued nothing new; the other reason stayed parked.
    expect((await log()).length, before.length);
    expect(await op(otherOp), before[otherOp]);
    expect(await db.recurringRuleDao.getRuleById(otherRule), otherRuleBefore);

    final logAfter = await log();
    final rulesAfter = await rules();
    await repository.repairRecurrenceEndDateOperations();
    expect(await log(), logAfter);
    expect(await rules(), rulesAfter);

    expect(await repository.push(), isNull);
    expect(gateway.appliedOperations, [parkedId, pendingId]);
    expect((await op(parkedId)).state, 'acknowledged');
    expect((await op(pendingId)).state, 'acknowledged');
    expect(await op(otherOp), before[otherOp]);
  });

  test('push repairs a record that has only the parked operation', () async {
    final ruleId = await seedRule();
    final parkedId = await queue(ruleId, isActive: 0);
    await park(parkedId);

    await repository.repairRecurrenceEndDateOperations();

    final row = await op(parkedId);
    expect(row.state, 'pending');
    expect((jsonDecode(row.payload) as Map)['end_date'], '2026-09-27');
    expectValid(row);

    expect(await repository.push(), isNull);
    expect(gateway.appliedOperations, [parkedId]);
  });

  test('push alone repairs and sends a lone parked operation', () async {
    final ruleId = await seedRule();
    final parkedId = await queue(ruleId, isActive: 0);
    await park(parkedId);

    expect(await repository.push(), isNull);

    expect(gateway.appliedOperations, [parkedId]);
    expect(gateway.sentPayloads.single['end_date'], '2026-09-27');
    expect((await op(parkedId)).state, 'acknowledged');
  });

  test(
    'a record with an in-flight or conflicted operation is skipped',
    () async {
      final (_, _, inFlightPending) = await seedDeviceState();
      await db.syncDao.markInFlight(
        inFlightPending,
        DateTime.utc(2026, 10, 13),
      );
      final (_, _, conflictPending) = await seedDeviceState();
      await db.syncDao.markConflict(
        conflictPending,
        DateTime.utc(2026, 10, 13),
      );
      final logBefore = await log();
      final rulesBefore = await rules();

      await repository.repairRecurrenceEndDateOperations();

      expect(await log(), logBefore);
      expect(await rules(), rulesBefore);
    },
  );

  test('a payload still invalid after the rewrite stays parked', () async {
    final ruleId = await seedRule();
    final parkedId = await queue(ruleId, isActive: 1);
    // A second defect the end-date rewrite does not fix.
    await queue(ruleId, isActive: 0, startTimeOfDay: '25:00');
    await park(parkedId);
    final logBefore = await log();
    final rulesBefore = await rules();

    await repository.repairRecurrenceEndDateOperations();

    expect(await log(), logBefore);
    expect(await rules(), rulesBefore);
    expect((await db.syncDao.firstPermanentOperation())?.operationId, parkedId);
  });

  test(
    'after the repair nothing is parked (warning triangle clears)',
    () async {
      await seedDeviceState();
      expect(await db.syncDao.firstPermanentOperation(), isNotNull);

      await repository.repairRecurrenceEndDateOperations();

      expect(await db.syncDao.firstPermanentOperation(), isNull);
    },
  );
}

class _Gateway implements SyncRemoteGateway {
  final appliedOperations = <String>[];
  final sentPayloads = <Map<String, dynamic>>[];
  var _version = 171;

  @override
  Future<Object?> compactHistory() async => null;

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
    appliedOperations.add(operationId);
    sentPayloads.add(payload);
    _version++;
    return {
      'status': 'applied',
      'server_version': _version,
      'change_id': _version,
      'server_timestamp': '2026-10-13T00:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => const <Object>[];
}
