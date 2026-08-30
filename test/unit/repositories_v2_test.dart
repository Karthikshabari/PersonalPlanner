import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/subtask.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/task_editor/data/subtask_repository.dart';
import 'package:personal_planner/features/task_editor/data/tag_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/core/utils/uuid.dart';

import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late SubtaskRepository subtasks;
  late TagRepository tags;
  late InboxRepository inbox;
  late CategoryRepository categories;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    subtasks = SubtaskRepository(db);
    tags = TagRepository(db);
    inbox = InboxRepository(db);
    categories = CategoryRepository(db);
    await categories.seedDefaultsIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Task> seedTask({String title = 'T', bool inboxItem = false}) =>
      tasks.insertTask(
        Task(
          id: '',
          title: title,
          isInbox: inboxItem,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

  group('SubtaskRepository', () {
    test('insert, watch ordered by sortOrder, toggle, soft-delete', () async {
      final task = await seedTask();
      final a = await subtasks.insertSubtask(
        Subtask(
          id: '',
          taskId: task.id,
          title: 'A',
          sortOrder: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final b = await subtasks.insertSubtask(
        Subtask(
          id: '',
          taskId: task.id,
          title: 'B',
          sortOrder: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      expect((await subtasks.getSubtasksForTask(task.id)).map((s) => s.title), [
        'A',
        'B',
      ]);

      final toggled = await subtasks.toggleSubtask(a.id);
      expect(toggled.isCompleted, isTrue);
      // Toggle back.
      expect((await subtasks.toggleSubtask(a.id)).isCompleted, isFalse);

      await subtasks.deleteSubtask(b.id);
      // Soft-deleted rows disappear from the watch query.
      await expectLater(
        subtasks.watchSubtasksForTask(task.id).first,
        completion(hasLength(1)),
      );
      // Row still present with deletedAt set.
      final raw = await (db.select(
        db.subtasks,
      )..where((s) => s.id.equals(b.id))).getSingle();
      expect(raw.deletedAt, isNotNull);
    });

    test('reorderSubtasks persists the given order', () async {
      final task = await seedTask();
      final ids = <String>[];
      for (final title in ['A', 'B', 'C']) {
        final s = await subtasks.insertSubtask(
          Subtask(
            id: '',
            taskId: task.id,
            title: title,
            sortOrder: ids.length,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        ids.add(s.id);
      }
      // Move A to the end.
      await subtasks.reorderSubtasks(task.id, [ids[1], ids[2], ids[0]]);
      final order = (await subtasks.getSubtasksForTask(task.id))
          .map((s) => s.title);
      expect(order, ['B', 'C', 'A']);
    });
  });

  group('TagRepository', () {
    test('getOrCreateByName is idempotent by name', () async {
      final t1 = await tags.getOrCreateByName('deep-work');
      final t2 = await tags.getOrCreateByName('deep-work');
      expect(t1.id, t2.id);
      expect(t1.id, generateDeterministicUuid('tag:deep-work'));
    });

    test(
      'attach/detach tags on a task; watchTagsForTask streams them',
      () async {
        final task = await seedTask();
        final deep = await tags.getOrCreateByName('deep-work');
        final admin = await tags.getOrCreateByName('admin');

        await tags.addTagToTask(task.id, deep.id);
        await tags.addTagToTask(task.id, admin.id);
        await expectLater(
          tags.watchTagsForTask(task.id).first,
          completion(hasLength(2)),
        );

        await tags.removeTagFromTask(task.id, admin.id);
        final remaining = await tags.getTagsForTask(task.id);
        expect(remaining.map((t) => t.name), ['deep-work']);

        // Deleting a tag detaches it everywhere.
        await tags.deleteTag(deep.id);
        expect(await tags.getTagsForTask(task.id), isEmpty);
        final all = await tags.watchAllTags().first;
        expect(all.any((t) => t.name == 'deep-work'), isFalse);
      },
    );
  });

  group('InboxRepository', () {
    test(
      'addToInbox creates an unscheduled inbox item surfaced by the stream',
      () async {
        await inbox.addToInbox('Buy milk');
        final items = await inbox.watchInboxItems().first;
        expect(items, hasLength(1));
        expect(items.single.task.title, 'Buy milk');
        expect(items.single.isOverdue, isFalse);
        expect(items.single.task.isInbox, isTrue);
        expect(items.single.task.startTime, isNull);
      },
    );

    test(
      'overdue scheduled tasks surface alongside inbox items with stamping',
      () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        await tasks.insertTask(
          Task(
            id: '',
            title: 'Past thing',
            startTime: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              8,
            ),
            endTime: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              9,
            ),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
        await inbox.addToInbox('Idea');

        final affected = await inbox.stampOverdue();
        expect(affected, 1);

        final items = await inbox.watchInboxItems().first;
        expect(
          items.map((i) => i.task.title),
          containsAll(['Idea', 'Past thing']),
        );
        final overdue = items.firstWhere((i) => i.task.title == 'Past thing');
        expect(overdue.isOverdue, isTrue);
        expect(overdue.task.missedAt, isNotNull);
        expect(overdue.task.missedAt!.length, 16); // YYYY-MM-DDTHH:mm

        // Stamping happens only once.
        expect(await inbox.stampOverdue(), 0);

        // Completed tasks are not overdue.
        final done = await seedTask(title: 'Done thing');
        await tasks.updateTask(done.copyWith(status: TaskStatus.completed));
        final after = await inbox.watchInboxItems().first;
        expect(after.map((i) => i.task.title), isNot(contains('Done thing')));
      },
    );

    test('scheduleItem clears the inbox flag and sets times', () async {
      final item = await inbox.addToInbox('Schedule me');
      // Tomorrow, so the scheduled block never counts as overdue
      // (a past-day planned task would surface in the inbox again).
      final day = addDays(DateTime.now(), 1);
      final start = DateTime(day.year, day.month, day.day, 10);
      final result = await inbox.scheduleItem(
        item.id,
        start,
        start.add(const Duration(hours: 1)),
      );
      expect(result.isInbox, isFalse);
      expect(result.startTime, start.toLocal());
      expect(result.status, TaskStatus.planned);
      expect(await inbox.watchInboxItems().first, isEmpty);
    });

    test('rescheduleOverdue creates linked copy and marks original', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final original = await tasks.insertTask(
        Task(
          id: '',
          title: 'Overdue work',
          categoryId: (await categories.getAllCategories()).first.id,
          startTime: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            8,
          ),
          endTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      final newStart = DateTime(2026, 8, 24, 14);
      final copy = await inbox.rescheduleOverdue(
        original.id,
        newStart,
        newStart.add(const Duration(hours: 1)),
      );

      expect(copy.rescheduledFromId, original.id);
      expect(copy.status, TaskStatus.planned);
      expect(copy.categoryId, original.categoryId); // fields carried over

      final updatedOriginal = await tasks.getTaskById(original.id);
      expect(updatedOriginal!.status, TaskStatus.rescheduled);
      expect(updatedOriginal.rescheduledToId, copy.id);
    });

    test(
      'history links reject self-links and direct cycles atomically',
      () async {
        final self = await seedTask(title: 'Self');
        await expectLater(
          tasks.updateTask(self.copyWith(rescheduledToId: self.id)),
          throwsStateError,
        );
        expect((await tasks.getTaskById(self.id))!.rescheduledToId, isNull);

        final first = await seedTask(title: 'First');
        final second = await seedTask(title: 'Second');
        await tasks.updateTask(first.copyWith(rescheduledToId: second.id));
        await expectLater(
          tasks.updateTask(second.copyWith(rescheduledToId: first.id)),
          throwsStateError,
        );
        expect((await tasks.getTaskById(second.id))!.rescheduledToId, isNull);
        expect((await tasks.getTaskById(first.id))!.rescheduledToId, second.id);
      },
    );
  });

  group('CategoryRepository CRUD support', () {
    test('deleteCategory nulls out tasks in the category', () async {
      final cat = (await categories.getAllCategories()).first;
      final task = await seedTask();
      await tasks.updateTask(task.copyWith(categoryId: cat.id));

      await categories.deleteCategory(cat.id);

      final reloaded = await tasks.getTaskById(task.id);
      expect(reloaded!.categoryId, isNull);
      // Active list no longer contains it (getCategoryById deliberately
      // still sees soft-deleted rows for sync).
      final active = await categories.getAllCategories();
      expect(active.map((c) => c.id), isNot(contains(cat.id)));
    });

    test('reorderCategories persists sort order', () async {
      final c1 = await categories.insertCategory(
        Category(
          id: '',
          name: 'Zed',
          colorHex: '#123456',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final c2 = await categories.insertCategory(
        Category(
          id: '',
          name: 'Alpha',
          colorHex: '#654321',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Put Alpha first, keeping all other categories after it.
      final others = (await categories.getAllCategories())
          .map((c) => c.id)
          .where((id) => id != c2.id && id != c1.id)
          .toList();
      await categories.reorderCategories([c2.id, ...others, c1.id]);
      final ordered = await categories.getAllCategories();
      expect(ordered.first.id, c2.id);
      expect(ordered.last.id, c1.id);
    });
  });
}
