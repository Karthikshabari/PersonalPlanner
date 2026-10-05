import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('pull FK isolation (DB-002)', () {
    Future<void> quarantinedParentScenario() async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _PageGateway();
      try {
        gateway.pages.add([
          _change(
            1,
            'tasks',
            'parent-task',
            _taskPayload(
              'parent-task',
              planTitleHistoryJson: '{"not":"an array"}',
            ),
          ),
          _change(2, 'subtasks', 'orphan-subtask', {
            'id': 'orphan-subtask',
            'task_id': 'parent-task',
            'title': 'Child',
            'is_completed': 0,
            'sort_order': 0,
            'created_at': _now.toIso8601String(),
            'updated_at': _now.toIso8601String(),
            'deleted_at': null,
          }),
        ]);
        final repository = SyncRepository.withGateway(db, gateway, 'account');

        final failure = await repository.pull();

        expect(failure, isNotNull);
        expect(failure!.kind, SyncFailureKind.invalidData);
        expect(await db.syncDao.getCursor('account'), 2);
        expect(await db.syncDao.getQuarantinedChanges('account'), hasLength(2));
        final subtasks = await db
            .customSelect('SELECT COUNT(*) AS c FROM subtasks')
            .getSingle();
        expect(subtasks.read<int>('c'), 0);

        gateway.pages.add([
          _change(3, 'tasks', 'healthy-task', _taskPayload('healthy-task')),
        ]);
        expect(await repository.pull(), isNull);
        expect(await db.syncDao.getCursor('account'), 3);
        expect(await db.taskDao.getTaskById('healthy-task'), isNotNull);
      } finally {
        await db.close();
      }
    }

    test(
      'quarantined parent and its child in one page: cursor advances, child '
      'quarantined, next pull succeeds',
      quarantinedParentScenario,
    );

    test('50 iterations never raise SqliteException(787)', () async {
      for (var i = 0; i < 50; i++) {
        try {
          await quarantinedParentScenario();
        } on SqliteException catch (error) {
          fail(
            'iteration $i raised SqliteException(${error.extendedResultCode})',
          );
        }
      }
    });

    test('reciprocal reschedule pair in one page still applies', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _PageGateway()
        ..pages.add([
          _change(
            1,
            'tasks',
            'reschedule-a',
            _taskPayload(
              'reschedule-a',
              status: 'rescheduled',
              to: 'reschedule-b',
            ),
          ),
          _change(
            2,
            'tasks',
            'reschedule-b',
            _taskPayload(
              'reschedule-b',
              status: 'rescheduled',
              from: 'reschedule-a',
            ),
          ),
        ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result, isNull);
        expect(
          (await db.taskDao.getTaskById('reschedule-a'))!.rescheduledToId,
          'reschedule-b',
        );
        expect(
          (await db.taskDao.getTaskById('reschedule-b'))!.rescheduledFromId,
          'reschedule-a',
        );
        expect(await db.syncDao.getCursor('account'), 2);
        expect(await db.syncDao.getQuarantinedChanges('account'), isEmpty);
      } finally {
        await db.close();
      }
    });
  });
}

final _now = DateTime.utc(2026, 1, 1, 9);

Map<String, dynamic> _change(
  int changeId,
  String table,
  String recordId,
  Map<String, dynamic> payload,
) => {
  'change_id': changeId,
  'operation_id': 'remote-$table-$recordId-$changeId',
  'table_name': table,
  'record_id': recordId,
  'operation': 'insert',
  'server_version': changeId,
  'server_timestamp': _now.toIso8601String(),
  'payload': payload,
};

Map<String, dynamic> _taskPayload(
  String id, {
  String status = 'planned',
  String? from,
  String? to,
  String? planTitleHistoryJson,
}) => {
  'id': id,
  'title': id,
  'description': null,
  'start_time': null,
  'end_time': null,
  'estimated_duration_min': null,
  'actual_duration_min': null,
  'manual_duration_adjustment_min': 0,
  'category_id': null,
  'priority': 0,
  'status': status,
  'notes': null,
  'recurring_rule_id': null,
  'rescheduled_from_id': from,
  'rescheduled_to_id': to,
  'is_inbox': 0,
  'missed_at': null,
  'plan_title_history_json': ?planTitleHistoryJson,
  'created_at': _now.toIso8601String(),
  'updated_at': _now.toIso8601String(),
  'deleted_at': null,
};

class _PageGateway implements SyncRemoteGateway {
  @override
  Future<Object?> compactHistory() async => null;

  final pages = <List<Object?>>[];

  @override
  Future<Object?> getCapabilities() async => const <String, Object?>{};

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
  }) => throw UnimplementedError();

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    if (pages.isEmpty) return const <Object>[];
    return pages.removeAt(0);
  }
}
