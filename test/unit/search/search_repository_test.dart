import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/search/data/search_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late SearchRepository search;
  final day = DateTime(2026, 8, 24);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    search = SearchRepository(db);
  });

  tearDown(() => db.close());

  Task task({String title = 'Deep work', String? description}) => Task(
    id: '',
    title: title,
    description: description,
    startTime: day.add(const Duration(hours: 9)),
    endTime: day.add(const Duration(hours: 10)),
    createdAt: day,
    updatedAt: day,
  );

  test(
    'FTS searches title/description and safely handles operators/unicode',
    () async {
      final saved = await tasks.insertTask(
        task(title: 'Quote "deep work"', description: 'Ünicode café notes'),
      );

      expect((await search.search('deep')).single.id, saved.id);
      expect((await search.search('café')).single.id, saved.id);
      expect(await search.search('" OR (NEAR(foo bar'), isEmpty);
      expect(await search.search('*** ""'), isEmpty);
      expect(await search.search(''), isEmpty);
      expect(SearchRepository.normalizeQuery('foo OR "bar'), isNotNull);
    },
  );

  test(
    'insert, edit, soft-delete, restore and hard-delete follow FTS lifecycle',
    () async {
      final saved = await tasks.insertTask(task(title: 'Original title'));
      expect((await search.search('Original')).single.id, saved.id);

      await tasks.updateTask(saved.copyWith(title: 'Edited title'));
      expect(await search.search('Original'), isEmpty);
      expect((await search.search('Edited')).single.id, saved.id);

      await tasks.deleteTask(saved.id);
      expect(await search.search('Edited'), isEmpty);

      final deleted = await tasks.getTaskById(saved.id);
      await tasks.restoreTask(deleted!);
      expect((await search.search('Edited')).single.id, saved.id);

      await tasks.hardDeleteTask(saved.id);
      expect(await search.search('Edited'), isEmpty);
    },
  );

  test('Inbox search returns the raw-content preview, not the placeholder title', () async {
    final capture = await TaskRepository(db).insertTask(
      Task(
        id: '',
        title: 'Inbox capture',
        description: '\n  First line\nSecond paragraph',
        isInbox: true,
        inboxContentVersion: 1,
        createdAt: day,
        updatedAt: day,
      ),
    );
    final result = (await search.search('paragraph')).single;
    expect(result.id, capture.id);
    expect(result.title, 'First line');
    expect(result.isInbox, isTrue);
  });
}
