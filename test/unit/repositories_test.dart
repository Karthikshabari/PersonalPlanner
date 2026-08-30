import '../helpers/sqlite_setup.dart' as sqlite_setup;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/enums/priority.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

void main() {
  sqlite_setup.setupSqliteForTests();
  late AppDatabase db;
  late TaskRepository taskRepo;
  late CategoryRepository categoryRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    taskRepo = TaskRepository(db);
    categoryRepo = CategoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Task newTask({
    String title = 'Test task',
    DateTime? start,
    DateTime? end,
    bool inbox = false,
  }) {
    final now = DateTime.now();
    return Task(
      id: '',
      title: title,
      startTime: start,
      endTime: end,
      isInbox: inbox,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('TaskRepository', () {
    test('insertTask assigns UUIDv7 id and timestamps', () async {
      final day = DateTime(2026, 7, 23, 10);
      final inserted = await taskRepo.insertTask(
        newTask(start: day, end: day.add(const Duration(hours: 1))),
      );
      expect(inserted.id, isNotEmpty);
      expect(inserted.id.length, greaterThanOrEqualTo(32));
      final fetched = await taskRepo.getTaskById(inserted.id);
      expect(fetched, isNotNull);
      expect(fetched!.title, 'Test task');
      expect(fetched.status, TaskStatus.planned);
      expect(fetched.isInbox, false);
    });

    test('updateTask persists field changes', () async {
      final day = DateTime(2026, 7, 23, 9);
      final inserted = await taskRepo.insertTask(
        newTask(
          title: 'Before',
          start: day,
          end: day.add(const Duration(minutes: 30)),
        ),
      );
      await taskRepo.updateTask(
        inserted.copyWith(
          title: 'After',
          priority: Priority.high,
          status: TaskStatus.inProgress,
          categoryId: null,
        ),
      );
      final fetched = await taskRepo.getTaskById(inserted.id);
      expect(fetched!.title, 'After');
      expect(fetched.priority, Priority.high);
      expect(fetched.status, TaskStatus.inProgress);
    });

    test('deleteTask soft-deletes and watchTasksForDay hides it', () async {
      final day = DateTime(2026, 7, 23, 10);
      final inserted = await taskRepo.insertTask(
        newTask(start: day, end: day.add(const Duration(hours: 1))),
      );
      final before = await taskRepo
          .watchTasksForDay(DateTime(2026, 7, 23))
          .first;
      expect(before, hasLength(1));
      await taskRepo.deleteTask(inserted.id);
      final after = await taskRepo
          .watchTasksForDay(DateTime(2026, 7, 23))
          .first;
      expect(after, isEmpty);
      final fetched = await taskRepo.getTaskById(inserted.id);
      expect(fetched!.deletedAt, isNotNull);
      final rawRow = await db.select(db.tasks).get();
      expect(rawRow, hasLength(1));
      expect(rawRow.single.deletedAt, isNotNull);
    });

    test('watchTasksForDay returns only that day, excludes inbox', () async {
      final dayA = DateTime(2026, 7, 23, 10);
      final dayB = DateTime(2026, 7, 24, 10);
      await taskRepo.insertTask(
        newTask(
          title: 'On A',
          start: dayA,
          end: dayA.add(const Duration(hours: 1)),
        ),
      );
      await taskRepo.insertTask(
        newTask(
          title: 'On B',
          start: dayB,
          end: dayB.add(const Duration(hours: 1)),
        ),
      );
      await taskRepo.insertTask(newTask(title: 'Inbox item', inbox: true));
      final stream = await taskRepo
          .watchTasksForDay(DateTime(2026, 7, 23))
          .first;
      expect(stream.map((t) => t.title), ['On A']);
    });

    test(
      'day queries normalize arbitrary times and exclude next midnight',
      () async {
        final dayStart = DateTime(2026, 7, 23);
        await taskRepo.insertTask(
          newTask(
            title: 'Late task',
            start: dayStart.add(const Duration(hours: 23, minutes: 30)),
            end: dayStart.add(const Duration(days: 1, minutes: 30)),
          ),
        );
        await taskRepo.insertTask(
          newTask(
            title: 'Next day midnight',
            start: dayStart.add(const Duration(days: 1)),
            end: dayStart.add(const Duration(days: 1, hours: 1)),
          ),
        );

        final rows = await taskRepo
            .watchTasksForDay(
              dayStart.add(const Duration(hours: 18, minutes: 30)),
            )
            .first;
        expect(rows.map((task) => task.title), ['Late task']);
      },
    );

    test('repository enforces the Inbox scheduling invariant', () async {
      final day = DateTime(2026, 7, 23, 10);
      final stored = await taskRepo.insertTask(
        newTask(
          title: 'Inbox with stale schedule',
          start: day,
          end: day.add(const Duration(hours: 1)),
          inbox: true,
        ),
      );

      expect(stored.isInbox, isTrue);
      expect(stored.startTime, isNull);
      expect(stored.endTime, isNull);
      expect(await taskRepo.watchTasksForDay(day).first, isEmpty);
    });

    test('watchTasksForDay emits updates on insert', () async {
      final day = DateTime(2026, 7, 23, 10);
      final stream = taskRepo.watchTasksForDay(DateTime(2026, 7, 23));
      expectLater(stream.map((l) => l.length), emitsInOrder([0, 1]));
      await Future<void>.delayed(Duration.zero);
      await taskRepo.insertTask(
        newTask(start: day, end: day.add(const Duration(hours: 1))),
      );
    });
  });

  group('CategoryRepository', () {
    test('seedDefaultsIfEmpty creates the 4 default categories once', () async {
      await categoryRepo.seedDefaultsIfEmpty();
      var categories = await categoryRepo.getAllCategories();
      expect(categories, hasLength(4));
      expect(
        categories.map((c) => c.name),
        containsAll(['Work', 'Personal', 'Health', 'Learning']),
      );
      final workColor = categories.firstWhere((c) => c.name == 'Work').colorHex;
      expect(workColor.toUpperCase(), '#4285F4');
      expect(
        categories.firstWhere((c) => c.name == 'Work').id,
        CategoryRepository.defaultCategoryId('work'),
      );
      await categoryRepo.seedDefaultsIfEmpty();
      categories = await categoryRepo.getAllCategories();
      expect(categories, hasLength(4));
    });

    test('category CRUD round-trip', () async {
      await categoryRepo.seedDefaultsIfEmpty();
      final created = await categoryRepo.insertCategory(
        Category(
          id: '',
          name: 'Side Project',
          colorHex: '#FF8800',
          sortOrder: 99,
          isFocus: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final fetched = await categoryRepo.getCategoryById(created.id);
      expect(fetched!.name, 'Side Project');
      expect(fetched.isFocus, true);

      await categoryRepo.updateCategory(fetched.copyWith(name: 'Renamed'));
      final renamed = await categoryRepo.getCategoryById(created.id);
      expect(renamed!.name, 'Renamed');

      await categoryRepo.deleteCategory(created.id);
      final all = await categoryRepo.watchAllCategories().first;
      expect(all.map((c) => c.id), isNot(contains(created.id)));
    });
  });
}
