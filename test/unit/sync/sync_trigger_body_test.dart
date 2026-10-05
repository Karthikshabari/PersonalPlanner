import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  Future<int> outboxCount(AppDatabase db) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_log')
        .getSingle();
    return row.read<int>('c');
  }

  test('no-op update creates no outbox row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      final task = await TaskRepository(
        db,
      ).insertTask(Task(id: '', title: 'Same', createdAt: now, updatedAt: now));
      expect(await outboxCount(db), 1);

      final row = (await db.taskDao.getTaskById(task.id))!;
      await db.taskDao.updateTask(
        row.copyWith(updatedAt: row.updatedAt.add(const Duration(minutes: 5))),
      );
      expect(await outboxCount(db), 1);

      await db.taskDao.updateTask(row.copyWith(title: 'Changed'));
      expect(await outboxCount(db), 2);
    } finally {
      await db.close();
    }
  });

  test('payload revision equals the stored row revision', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 1, 1, 9);
      final task = await TaskRepository(db).insertTask(
        Task(id: '', title: 'Before', createdAt: now, updatedAt: now),
      );
      await db.customStatement('UPDATE tasks SET title = ? WHERE id = ?', [
        'x',
        task.id,
      ]);
      final op = await db
          .customSelect(
            "SELECT json_extract(payload, '\$._planner_revision') AS rev "
            'FROM sync_log ORDER BY seq DESC LIMIT 1',
          )
          .getSingle();
      final stored = await db
          .customSelect(
            'SELECT revision FROM tasks WHERE id = ?',
            variables: [Variable<String>(task.id)],
          )
          .getSingle();
      expect(op.read<int>('rev'), stored.read<int>('revision'));
      expect(stored.read<int>('revision'), greaterThan(1));
    } finally {
      await db.close();
    }
  });

  test('existing databases pick up new trigger bodies', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_trigger_v');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'planner.sqlite3'));

    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement(
      "INSERT OR REPLACE INTO app_settings(key, value) "
      "VALUES ('schema.sync_trigger_version', '1')",
    );
    // Stand in for a body installed by an older client; the trigger count
    // stays complete, so only the version stamp can force a rebuild.
    await first.customStatement('DROP TRIGGER sync_tasks_update');
    await first.customStatement(
      'CREATE TRIGGER sync_tasks_update AFTER UPDATE OF title ON tasks '
      'BEGIN SELECT 1; END',
    );
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    try {
      final trigger = await second
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'sync_tasks_update'",
          )
          .getSingle();
      expect(trigger.read<String>('sql'), contains('IS NOT OLD.title'));
      expect(
        await second.syncDao.getSetting('schema.sync_trigger_version'),
        '${AppDatabase.syncTriggerVersion}',
      );
    } finally {
      await second.close();
    }
  });
}
