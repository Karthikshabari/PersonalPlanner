import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';

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
}
