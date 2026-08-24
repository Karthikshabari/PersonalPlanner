import '../helpers/sqlite_setup.dart' as sqlite_setup;
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

void main() {
  sqlite_setup.setupSqliteForTests();
  test('data persists across database restart (SQLite file)', () async {
    final tempDir = await Directory.systemTemp.createTemp('planner_persist');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'planner.sqlite3');

    final db1 = AppDatabase(NativeDatabase(File(dbPath)));
    final taskRepo1 = TaskRepository(db1);
    final categoryRepo1 = CategoryRepository(db1);

    await categoryRepo1.seedDefaultsIfEmpty();
    final day = DateTime(2026, 7, 23, 14);
    final inserted = await taskRepo1.insertTask(Task(
      id: '',
      title: 'Persistent task',
      startTime: day,
      endTime: day.add(const Duration(hours: 2)),
      estimatedDurationMin: 120,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(File(dbPath)));
    final taskRepo2 = TaskRepository(db2);
    final categoryRepo2 = CategoryRepository(db2);

    final fetched = await taskRepo2.getTaskById(inserted.id);
    expect(fetched, isNotNull);
    expect(fetched!.title, 'Persistent task');
    expect(fetched.startTime!.hour, 14);
    expect(fetched.endTime!.difference(fetched.startTime!),
        const Duration(hours: 2));

    final categories = await categoryRepo2.getAllCategories();
    expect(categories, hasLength(4));
    await categoryRepo2.seedDefaultsIfEmpty();
    expect(await categoryRepo2.getAllCategories(), hasLength(4));

    await db2.close();
  });
}
