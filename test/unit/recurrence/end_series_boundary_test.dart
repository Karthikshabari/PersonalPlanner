import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_aggregate_command.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// UAT-003: ending a series at its first occurrence must never leave a rule
/// whose end date precedes its start date (sync parks such a rule forever).
void main() {
  setupSqliteForTests();

  final start = DateTime(2026, 9, 27);

  late AppDatabase db;
  late RecurringRepository rules;
  late RecurrenceService recurrence;
  late TaskRepository tasks;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    rules = RecurringRepository(db);
    recurrence = RecurrenceService(db, clock: () => DateTime(2026, 1, 1));
    tasks = TaskRepository(db);
    await rules.createRule(
      RecurringRule(
        id: 'rule-end',
        rrule: 'FREQ=DAILY',
        taskTitle: 'Daily',
        durationMin: 30,
        startTimeOfDay: '09:00',
        startDate: start,
        createdAt: start,
        updatedAt: start,
      ),
    );
    for (var day = 0; day < 3; day++) {
      await recurrence.materializeForDate(start.add(Duration(days: day)));
    }
  });

  tearDown(() => db.close());

  String occurrenceId(String date) =>
      generateDeterministicUuid('recurring-occurrence:rule-end:$date');

  /// The same mutation the Day view runs for "All future occurrences".
  RecurrenceAggregateCommand endSeriesCommand(DateTime boundary, String id) =>
      RecurrenceAggregateCommand(
        database: db,
        ruleId: 'rule-end',
        description: 'End recurring series',
        mutation: () async {
          await tasks.deleteTask(id);
          await rules.endSeriesBefore('rule-end', boundary);
          await recurrence.deleteMaterializedFuture(
            'rule-end',
            boundary,
            keepTaskId: id,
          );
        },
      );

  /// Validates every queued payload the way push does before sending it.
  Future<void> expectEveryPayloadValid() async {
    final rows = await db.select(db.syncLog).get();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(jsonDecode(row.payload) as Map);
      for (final key in const {
        '_planner_payload_version',
        '_planner_revision',
        'user_id',
        'server_version',
        'change_id',
        'server_timestamp',
      }) {
        payload.remove(key);
      }
      expect(
        () => SyncPayloadValidator.validate(
          SyncRemoteChange(
            changeId: 0,
            operationId: row.operationId,
            tableName: row.entityTableName,
            recordId: row.recordId,
            operation: row.operation,
            serverVersion: row.expectedServerVersion ?? 0,
            serverTimestamp: DateTime.now().toUtc(),
            payload: payload,
          ),
        ),
        returnsNormally,
        reason: '${row.entityTableName} ${row.operation} ${row.payload}',
      );
    }
  }

  test('ending at the first occurrence deletes the rule', () async {
    await endSeriesCommand(start, occurrenceId('2026-09-27')).execute();

    final rule = (await db.recurringRuleDao.getRuleById('rule-end'))!;
    expect(rule.deletedAt, isNotNull);
    expect(rule.isActive, isFalse);
    expect(rule.endDate, isNull);
    for (final date in const ['2026-09-27', '2026-09-28', '2026-09-29']) {
      expect(
        (await db.taskDao.getTaskById(occurrenceId(date)))!.deletedAt,
        isNotNull,
      );
    }
    await expectEveryPayloadValid();
  });

  test('ending at a later occurrence sets the day before', () async {
    final boundary = start.add(const Duration(days: 2));
    await endSeriesCommand(boundary, occurrenceId('2026-09-29')).execute();

    final rule = (await db.recurringRuleDao.getRuleById('rule-end'))!;
    expect(rule.deletedAt, isNull);
    expect(rule.isActive, isFalse);
    expect(rule.endDate, '2026-09-28');
    await expectEveryPayloadValid();
  });

  test('Undo after ending at the first occurrence restores the rule', () async {
    final command = endSeriesCommand(start, occurrenceId('2026-09-27'));
    await command.execute();
    await command.undo();

    final rule = (await db.recurringRuleDao.getRuleById('rule-end'))!;
    expect(rule.deletedAt, isNull);
    expect(rule.isActive, isTrue);
    expect(rule.endDate, isNull);
    await expectEveryPayloadValid();
  });

  test('setEndDate refuses a date before the start', () async {
    final before = await db.recurringRuleDao.getRuleById('rule-end');
    final logBefore = (await db.select(db.syncLog).get()).length;

    await expectLater(
      rules.setEndDate('rule-end', DateTime(2026, 9, 26)),
      throwsArgumentError,
    );

    expect(await db.recurringRuleDao.getRuleById('rule-end'), before);
    expect((await db.select(db.syncLog).get()).length, logBefore);
  });
}
