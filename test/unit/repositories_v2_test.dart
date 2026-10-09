import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/subtask.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
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
      'rename then recreate of the original deterministic name creates a fresh identity',
      () async {
        final original = await tags.getOrCreateByName('deep-work');
        await tags.updateTag(original.copyWith(name: 'focused'));

        final recreated = await tags.getOrCreateByName('deep-work');
        expect(recreated.id, isNot(original.id));
        expect(recreated.name, 'deep-work');
        expect(
          (await tags.watchAllTags().first).map((t) => t.name),
          unorderedEquals(['focused', 'deep-work']),
        );
      },
    );

    test('old name of a renamed tag can be created again', () async {
      final first = await tags.getOrCreateByName('work');
      await tags.updateTag(first.copyWith(name: 'office'));

      final again = await tags.getOrCreateByName('work');
      expect(again.name, 'work');
      expect(again.id, isNot(first.id));
      expect(again.deletedAt, isNull);
      expect(
        (await tags.watchAllTags().first).map((t) => t.name),
        unorderedEquals(['office', 'work']),
      );
    });

    test('normalizeTagKey trims, collapses inner spaces and lower-cases', () {
      expect(TagRepository.normalizeTagKey('  Learn  \t C  '), 'learn c');
      expect(TagRepository.normalizeTagKey('LEARN C'), 'learn c');
      expect(TagRepository.normalizeTagKey('   '), '');
    });

    test('findByNameIgnoringCase finds active tags only', () async {
      final learn = await tags.getOrCreateByName('Learn C');
      expect((await tags.findByNameIgnoringCase('learn c'))?.id, learn.id);
      expect((await tags.findByNameIgnoringCase('  LEARN   C '))?.id, learn.id);
      expect(await tags.findByNameIgnoringCase('learn'), isNull);
      expect(await tags.findByNameIgnoringCase('   '), isNull);
      await tags.deleteTag(learn.id);
      expect(await tags.findByNameIgnoringCase('learn c'), isNull);
    });

    test('findByNameIgnoringCase prefers the tag created first', () async {
      final first = await tags.getOrCreateByName('Learn C');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await tags.getOrCreateByName('learn c');
      expect(second.id, isNot(first.id));
      expect((await tags.findByNameIgnoringCase('LEARN C'))?.id, first.id);
    });

    test('getOrCreateForName returns the existing tag for a case or space '
        'variant', () async {
      final existing = await tags.getOrCreateByName('Learn C');
      for (final variant in ['learn c', '  Learn C  ', 'Learn  C', 'LEARN C']) {
        final found = await tags.getOrCreateForName(variant);
        expect(found.id, existing.id, reason: variant);
        expect(found.name, 'Learn C');
      }
      expect(await tags.watchAllTags().first, hasLength(1));
    });

    test(
      'getOrCreateForName keeps the deterministic id for a new name',
      () async {
        final created = await tags.getOrCreateForName('  Sketching  ');
        expect(created.name, 'Sketching');
        expect(created.id, generateDeterministicUuid('tag:Sketching'));
      },
    );

    test('getOrCreateForName rejects a blank name', () async {
      await expectLater(tags.getOrCreateForName('   '), throwsArgumentError);
      await expectLater(tags.getOrCreateForName(''), throwsArgumentError);
    });

    test(
      'getUsage counts live, non-Inbox blocks and finds the first date',
      () async {
        final tag = await tags.getOrCreateByName('Learn C');
        expect((await tags.getUsage(tag.id)).blockCount, 0);
        expect((await tags.getUsage(tag.id)).firstBlockDate, isNull);

        Future<Task> block(String title, DateTime start, {String? tagId}) =>
            tasks.insertTask(
              Task(
                id: '',
                title: title,
                startTime: start,
                endTime: start.add(const Duration(hours: 1)),
                tagId: tagId,
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
            );

        // 23:30 planner time (Asia/Kolkata) is still the 6th, not the UTC date.
        await block('late', DateTime(2026, 10, 6, 23, 30), tagId: tag.id);
        await block('later', DateTime(2026, 10, 9, 8), tagId: tag.id);
        final deleted = await block(
          'deleted',
          DateTime(2026, 10, 2, 8),
          tagId: tag.id,
        );
        await tasks.deleteTask(deleted.id);
        await block('untagged', DateTime(2026, 10, 1, 8));

        final usage = await tags.getUsage(tag.id);
        expect(usage.blockCount, 2);
        expect(usage.firstBlockDate, '2026-10-06');
      },
    );

    test('deleteTag refuses a tag that belongs to an experiment', () async {
      final experiment = await ExperimentRepository(db).createExperiment(
        name: 'Learn C',
        startDate: '2026-10-01',
        endDate: '2026-10-30',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      await expectLater(
        tags.deleteTag(experiment.tagId),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Tag ${experiment.tagId} belongs to an experiment and cannot be '
                'removed',
          ),
        ),
      );
      await expectLater(
        db.tagDao.softDeleteTag(experiment.tagId, DateTime.now()),
        throwsStateError,
      );
      expect((await tags.findByNameIgnoringCase('learn c')), isNotNull);
    });

    test('deleteTag still works for a plain tag', () async {
      final plain = await tags.getOrCreateByName('plain');
      await tags.deleteTag(plain.id);
      expect(await tags.findByNameIgnoringCase('plain'), isNull);
    });

    test('watchTagOptions flags tags that have an experiment', () async {
      await tags.getOrCreateByName('plain');
      final experiment = await ExperimentRepository(db).createExperiment(
        name: 'Learn C',
        startDate: '2026-10-01',
        endDate: '2026-10-30',
        weekdayTargetMin: 60,
        weekendTargetMin: 90,
        checkInEveryDays: 7,
      );
      final options = await db.tagDao.watchTagOptions().first;
      expect(
        {for (final o in options) o.name: o.hasExperiment},
        {'Learn C': true, 'plain': false},
      );
      expect(options.firstWhere((o) => o.hasExperiment).id, experiment.tagId);
    });

    test(
      'a task keeps its tag when the tag is cleared from other blocks',
      () async {
        final tag = await tags.getOrCreateByName('Learn C');
        final task = await tasks.insertTask(
          Task(
            id: '',
            title: 'B',
            startTime: DateTime(2026, 10, 6, 9),
            endTime: DateTime(2026, 10, 6, 10),
            tagId: tag.id,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
        await tasks.updateTask(task.copyWith(tagId: null));
        expect((await tasks.getTaskById(task.id))!.tagId, isNull);
        expect(await tags.findByNameIgnoringCase('Learn C'), isNotNull);
      },
    );

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
        const raw = '  Buy milk\n\n  with details\n';
        await inbox.addToInbox(raw, dueDate: '2026-02-28');
        final items = await inbox.watchInboxItems().first;
        expect(items, hasLength(1));
        expect(items.single.task.title, 'Inbox capture');
        expect(items.single.task.description, raw);
        expect(items.single.task.inboxContentVersion, 1);
        expect(items.single.task.dueDate, '2026-02-28');
        expect(items.single.isOverdue, isFalse);
        expect(items.single.task.isInbox, isTrue);
        expect(items.single.task.startTime, isNull);
        expect(items.single.displayPreview, 'Buy milk');
      },
    );

    test('capture rejects blank content and malformed due dates', () async {
      expect(() => inbox.addToInbox(' \n\t'), throwsArgumentError);
      expect(
        () => inbox.addToInbox('Valid', dueDate: '2026-02-30'),
        throwsArgumentError,
      );
    });

    test('due date is independent, editable, removable, and retained on schedule', () async {
      final item = await inbox.addToInbox('Raw content', dueDate: '2026-09-12');
      final withDue = await tasks.getTaskWithRevision(item.id);
      await tasks.updateTask(
        item.copyWith(dueDate: null),
        expectedRevision: withDue!.$2,
      );
      expect((await tasks.getTaskById(item.id))!.dueDate, isNull);

      final restored = await tasks.getTaskWithRevision(item.id);
      await tasks.updateTask(
        (await tasks.getTaskById(item.id))!.copyWith(dueDate: '2026-09-12'),
        expectedRevision: restored!.$2,
      );
      final day = addDays(DateTime.now(), 1);
      final scheduled = await inbox.scheduleItem(
        item.id,
        DateTime(day.year, day.month, day.day, 10),
        DateTime(day.year, day.month, day.day, 11),
        title: 'Deliberate title',
        description: 'Raw content',
        replaceDescription: true,
      );
      expect(scheduled.dueDate, '2026-09-12');
      expect(scheduled.isInbox, isFalse);
    });

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
          containsAll(['Inbox capture', 'Past thing']),
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

    test(
      'ordinary edits do not rescan an unrelated pre-existing cycle',
      () async {
        final first = await seedTask(title: 'First');
        final second = await seedTask(title: 'Second');
        await db.customStatement(
          'UPDATE tasks SET rescheduled_to_id = ? WHERE id = ?',
          [second.id, first.id],
        );
        await db.customStatement(
          'UPDATE tasks SET rescheduled_to_id = ? WHERE id = ?',
          [first.id, second.id],
        );

        final edited = await tasks.updateTask(first.copyWith(title: 'Renamed'));
        expect(edited.title, 'Renamed');
        expect((await tasks.getTaskById(first.id))!.title, 'Renamed');
      },
    );

    test('expected revision rejects a concurrent task edit', () async {
      final original = await seedTask(title: 'Original');
      final persisted = await db.taskDao.getTaskById(original.id);
      expect(persisted, isNotNull);

      await db.customStatement(
        'UPDATE tasks SET title = ?, revision = revision + 1 WHERE id = ?',
        ['Changed elsewhere', original.id],
      );

      await expectLater(
        tasks.updateTask(
          original.copyWith(title: 'Stale editor value'),
          expectedRevision: persisted!.revision,
        ),
        throwsStateError,
      );
      expect(
        (await tasks.getTaskById(original.id))!.title,
        'Changed elsewhere',
      );
    });
  });

  group('CategoryRepository CRUD support', () {
    test(
      'legacy seeded category is materialized before foreign-key rewrites',
      () async {
        await db.delete(db.categories).go();
        await db.delete(db.appSettings).go();
        final legacy = await categories.insertCategory(
          Category(
            id: 'legacy-work',
            name: 'Work',
            colorHex: '#4285F4',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final task = await seedTask(title: 'Legacy reference');
        await tasks.updateTask(task.copyWith(categoryId: legacy.id));
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: 'default_categories_seeded',
                value: 'true',
              ),
            );

        await categories.seedDefaultsIfEmpty();

        final stableId = CategoryRepository.defaultCategoryId('work');
        expect((await tasks.getTaskById(task.id))!.categoryId, stableId);
        expect((await categories.getCategoryById(stableId))!.name, 'Work');
        expect(
          (await categories.getCategoryById(legacy.id))!.deletedAt,
          isNotNull,
        );
      },
    );

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
