import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/settings/data/backup_codec.dart';
import 'package:personal_planner/features/settings/data/backup_database_applier.dart';
import 'package:personal_planner/features/settings/data/backup_merge_planner.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';

import '../../helpers/sqlite_setup.dart';

const _predecessorId = '01900000-0000-7000-8000-000000000001';
const _successorId = '01900000-0000-7000-8000-000000000002';

void main() {
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'merged reciprocal reschedule pair pushes without a dependency cycle',
    () async {
      final source = AppDatabase(NativeDatabase.memory());
      final target = AppDatabase(NativeDatabase.memory());
      final gateway = _ImmediateForeignKeyGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        // A completed reschedule: X.rescheduled_to_id = Y and
        // Y.rescheduled_from_id = X.
        await source.transaction(() async {
          await source.customStatement('PRAGMA defer_foreign_keys = ON');
          await source
              .into(source.tasks)
              .insert(
                TasksCompanion.insert(
                  id: _predecessorId,
                  title: 'Original',
                  status: const Value('rescheduled'),
                  rescheduledToId: const Value(_successorId),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          await source
              .into(source.tasks)
              .insert(
                TasksCompanion.insert(
                  id: _successorId,
                  title: 'Original',
                  rescheduledFromId: const Value(_predecessorId),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        });
        final incoming = await BackupCodec.exportData(source);

        // Same transaction shape as BackupService.importJson and
        // AnonymousDataAdoptionService.adopt, with outbound triggers live.
        await target.transaction(() async {
          await target.customStatement('PRAGMA defer_foreign_keys = ON');
          final local = await BackupCodec.exportData(target);
          final plan = BackupMergePlanner().build(
            incoming: incoming,
            local: local,
          );
          await BackupDatabaseApplier(target).applyMerge(plan);
        });

        final failure = await SyncRepository.withGateway(
          target,
          gateway,
          'account',
        ).push();

        expect(failure, isNull);
        expect(gateway.violations, isEmpty);
        expect(await target.syncDao.pendingCount(), 0);
        expect(gateway.sent.take(2).map((sent) => sent.operation), [
          'insert',
          'insert',
        ]);
        expect(gateway.remoteTasks[_predecessorId], {
          'rescheduled_from_id': null,
          'rescheduled_to_id': _successorId,
        });
        expect(gateway.remoteTasks[_successorId], {
          'rescheduled_from_id': _predecessorId,
          'rescheduled_to_id': null,
        });
        final predecessor = await (target.select(
          target.tasks,
        )..where((task) => task.id.equals(_predecessorId))).getSingle();
        final successor = await (target.select(
          target.tasks,
        )..where((task) => task.id.equals(_successorId))).getSingle();
        expect(predecessor.rescheduledToId, _successorId);
        expect(successor.rescheduledFromId, _predecessorId);
      } finally {
        await source.close();
        await target.close();
      }
    },
  );

  test(
    'one-directional reschedule link still orders the linked insert first',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _ImmediateForeignKeyGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        // The successor's insert is queued first, so chronology alone would
        // send it before the task it links to.
        await db.transaction(() async {
          await db.customStatement('PRAGMA defer_foreign_keys = ON');
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: _successorId,
                  title: 'Successor',
                  rescheduledFromId: const Value(_predecessorId),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: _predecessorId,
                  title: 'Predecessor',
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        });

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        expect(failure, isNull);
        expect(gateway.violations, isEmpty);
        expect(
          gateway.sent.map((sent) => (sent.recordId, sent.operation)).toList(),
          [(_predecessorId, 'insert'), (_successorId, 'insert')],
        );
      } finally {
        await db.close();
      }
    },
  );
}

/// Models the remote tasks table: reschedule foreign keys are checked
/// immediately inside each single-operation RPC transaction.
class _ImmediateForeignKeyGateway implements SyncRemoteGateway {
  final sent = <({String recordId, String operation})>[];
  final violations = <String>[];
  final remoteTasks = <String, Map<String, String?>>{};
  var _version = 0;

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
    sent.add((recordId: recordId, operation: operation));
    if (tableName == 'tasks') {
      if (operation == 'update' && !remoteTasks.containsKey(recordId)) {
        violations.add('update before insert: $recordId');
      }
      final links = <String, String?>{
        'rescheduled_from_id': payload['rescheduled_from_id']?.toString(),
        'rescheduled_to_id': payload['rescheduled_to_id']?.toString(),
      };
      for (final link in links.entries) {
        final target = link.value;
        if (target != null && !remoteTasks.containsKey(target)) {
          violations.add('${link.key} of $recordId references $target');
          throw StateError(
            'insert or update on table "tasks" violates foreign key constraint',
          );
        }
      }
      remoteTasks[recordId] = links;
    }
    _version++;
    return {
      'status': 'applied',
      'server_version': _version,
      'change_id': _version,
      'server_timestamp': '2026-01-02T00:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async => const <Object>[];
}
