import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/migration_schema.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('quarantined changes are exposed from durable local settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.syncDao.recordQuarantinedChange(
        'account-1',
        42,
        'Malformed task payload',
        rawChange: {
          'table_name': 'tasks',
          'record_id': 'task-42',
          'operation': 'update',
        },
      );

      final records = await db.syncDao.watchQuarantinedChanges().first;
      expect(records, hasLength(1));
      expect(records.single.key, 'sync.quarantine.account-1.42');
      expect(records.single.value, contains('Malformed task payload'));

      final decoded = SyncQuarantinedChange.fromSetting(
        records.single.key,
        jsonEncode({
          'account_id': 'account-1',
          'change_id': 42,
          'diagnostic': 'Malformed task payload',
          'raw_change': {
            'table_name': 'tasks',
            'record_id': 'task-42',
            'operation': 'update',
          },
        }),
      );
      expect(decoded.tableName, 'tasks');
      expect(decoded.recordId, 'task-42');
      expect(decoded.operation, 'update');
    } finally {
      await db.close();
    }
  });

  test('retired permanent operations do not remain active failures', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'permanent-category',
              name: 'Category',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        'permanent-category',
      )).single;
      await db.syncDao.markPermanentError(
        operation.operationId,
        now: now,
        error: 'Invalid payload',
      );
      expect(await db.syncDao.firstPermanentOperation(), isNotNull);

      expect(
        await db.syncDao.retirePendingOperations(
          'categories',
          'permanent-category',
        ),
        1,
      );
      expect(await db.syncDao.firstPermanentOperation(), isNull);
      expect(
        (await db.syncDao.getOperation(operation.operationId))?.lastError,
        isNull,
      );
    } finally {
      await db.close();
    }
  });

  test('watchOutboxSignal emits on enqueue and acknowledge', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final emissions = <({int outstanding, int newestSeq})>[];
      final subscription = db.syncDao.watchOutboxSignal().listen(emissions.add);
      Future<void> settle(int count) async {
        for (var i = 0; i < 50 && emissions.length < count; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await settle(1);
      expect(emissions.first, (outstanding: 0, newestSeq: 0));

      final now = DateTime.utc(2026, 1, 1, 9);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'signal-category',
              name: 'Category',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await settle(2);
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        'signal-category',
      )).single;
      expect(emissions[1].outstanding, 1);
      final newestSeq = emissions[1].newestSeq;
      expect(newestSeq, greaterThan(0));

      await db.syncDao.markAcknowledged(operation.operationId, now);
      await settle(3);
      expect(emissions[2], (outstanding: 0, newestSeq: newestSeq));
      await subscription.cancel();
    } finally {
      await db.close();
    }
  });

  test(
    'pruneAcknowledgedOperations deletes only old acknowledged rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final now = DateTime.now().toUtc();
        Future<void> enqueue(String id, String state, Duration age) =>
            db.syncDao.enqueueOperation(
              SyncLogCompanion.insert(
                operationId: id,
                entityTableName: 'tasks',
                recordId: 'record-$id',
                operation: 'update',
                payload: '{}',
                state: Value(state),
                createdAt: now.subtract(age),
                updatedAt: now.subtract(age),
              ),
            );
        await enqueue(
          'acknowledged-old',
          'acknowledged',
          const Duration(days: 40),
        );
        await enqueue(
          'acknowledged-new',
          'acknowledged',
          const Duration(days: 1),
        );
        await enqueue('pending-old', 'pending', const Duration(days: 40));
        await enqueue('conflict-old', 'conflict', const Duration(days: 40));

        final deleted = await db.syncDao.pruneAcknowledgedOperations(
          olderThan: now.subtract(const Duration(days: 30)),
        );

        expect(deleted, 1);
        final remaining = await db.select(db.syncLog).get();
        expect(
          remaining.map((row) => row.operationId),
          unorderedEquals(['acknowledged-new', 'pending-old', 'conflict-old']),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'v8 reconciliation is not re-enqueued after its operations are pruned',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'planner_v8_reconciliation_prune',
      );
      final file = File('${directory.path}/planner.sqlite3');
      try {
        MigrationSchema.create(file, 8);
        final raw = sqlite3.sqlite3.open(file.path);
        raw.execute('''
          CREATE TABLE IF NOT EXISTS planner_migration_recovery (
            recovery_id TEXT NOT NULL PRIMARY KEY,
            table_name TEXT NOT NULL,
            row_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            reason TEXT NOT NULL,
            recovered_at TEXT NOT NULL
          )
        ''');
        raw.execute(
          'INSERT INTO planner_migration_recovery '
          '(recovery_id, table_name, row_id, payload, reason, recovered_at) '
          "VALUES ('v8:tasks:task-1', 'tasks', 'task-1', '{}', "
          "'Migrated legacy explicit Inbox content without trimming', "
          "'2026-01-01T00:00:00.000Z')",
        );
        raw.dispose();

        final first = AppDatabase(NativeDatabase(file));
        try {
          final operation = (await first.syncDao.getActiveOperationsForRecord(
            'tasks',
            'task-1',
          )).single;
          final acknowledgedAt = DateTime.now().toUtc().subtract(
            const Duration(days: 40),
          );
          await first.syncDao.markAcknowledged(
            operation.operationId,
            acknowledgedAt,
          );
          expect(
            await first.syncDao.pruneAcknowledgedOperations(
              olderThan: DateTime.now().toUtc().subtract(
                const Duration(days: 30),
              ),
            ),
            1,
          );
        } finally {
          await first.close();
        }

        final clear = sqlite3.sqlite3.open(file.path);
        clear.execute(
          "DELETE FROM app_settings WHERE key = 'schema.maintenance_version'",
        );
        clear.dispose();

        final reopened = AppDatabase(NativeDatabase(file));
        try {
          final count = await reopened
              .customSelect('SELECT COUNT(*) AS count FROM sync_log')
              .getSingle();
          expect(count.read<int>('count'), 0);
        } finally {
          await reopened.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
}
