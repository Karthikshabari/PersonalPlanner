import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/task_editor/domain/task_editor_save_command.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TaskRepository(database);
  });

  tearDown(() => database.close());

  test('rolls back the complete editor mutation on a late failure', () async {
    final task = await repository.insertTask(
      Task(
        id: 'editor-transaction-task',
        title: 'Before',
        createdAt: DateTime(2026, 8, 29),
        updatedAt: DateTime(2026, 8, 29),
      ),
    );
    final command = TaskEditorSaveCommand(database);

    await expectLater(
      command.execute(() async {
        await repository.updateTask(task.copyWith(title: 'After'));
        throw StateError('simulated tag failure');
      }),
      throwsStateError,
    );

    expect((await repository.getTaskById(task.id))!.title, 'Before');
    final outbox = await database.select(database.syncLog).get();
    expect(
      outbox,
      hasLength(1),
      reason: 'the rolled-back edit must not enqueue',
    );
  });
}
