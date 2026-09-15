import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/onboarding/providers/onboarding_provider.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'adoption is explicit, preserves source and is resumable by primary key',
    () async {
      final account = AppDatabase(NativeDatabase.memory());

      Future<AppDatabase> sourceFactory() async {
        final source = AppDatabase(NativeDatabase.memory());
        await source
            .into(source.categories)
            .insert(
              CategoriesCompanion.insert(
                id: '00000000-0000-7000-8000-000000000001',
                name: 'Anonymous',
                colorHex: '#4285F4',
                createdAt: DateTime.utc(2026, 1, 1),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            );
        await source
            .into(source.dayContexts)
            .insert(
              DayContextsCompanion.insert(
                id: generateDeterministicUuid('day-context:2026-01-02'),
                date: '2026-01-02',
                kind: 'travel',
                createdAt: DateTime.utc(2026, 1, 1),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            );
        return source;
      }

      try {
        final service = AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        );
        final first = await service.adopt();
        expect(first.copiedRecords, 2);
        expect(first.alreadyPresentRecords, 0);
        expect((await account.select(account.categories).get()).length, 1);
        expect((await account.select(account.dayContexts).get()).length, 1);
        expect(await account.syncDao.pendingCount(), 2);

        // A retry reads the still-existing source and does not create another
        // row or another outbound operation.
        final second = await service.adopt();
        expect(second.copiedRecords, 0);
        expect(second.alreadyPresentRecords, 2);
        expect((await account.select(account.categories).get()).length, 1);
        expect(await account.syncDao.pendingCount(), 2);
      } finally {
        await account.close();
      }
    },
  );

  test('adoption rejects differing content for an identical ID', () async {
    final account = AppDatabase(NativeDatabase.memory());
    const id = '00000000-0000-7000-8000-000000000002';
    await account
        .into(account.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: 'Account value',
            colorHex: '#4285F4',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<AppDatabase> sourceFactory() async {
      final source = AppDatabase(NativeDatabase.memory());
      await source
          .into(source.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              name: 'Anonymous value',
              colorHex: '#DB4437',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );
      return source;
    }

    try {
      await expectLater(
        AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        ).adopt(),
        throwsA(isA<AnonymousDataAdoptionException>()),
      );
      expect(
        (await account.categoryDao.getCategoryById(id))!.name,
        'Account value',
      );
    } finally {
      await account.close();
    }
  });

  test(
    'independently seeded defaults adopt a task and retain one category',
    () async {
      final account = AppDatabase(NativeDatabase.memory());
      await CategoryRepository(account).seedDefaultsIfEmpty();
      final destinationTask = await _insertTask(
        account,
        id: '00000000-0000-7000-8000-000000000010',
        title: 'Existing account task',
      );
      final pendingBefore = await account.syncDao.pendingCount();

      Future<AppDatabase> sourceFactory() async {
        final source = AppDatabase(NativeDatabase.memory());
        await CategoryRepository(source).seedDefaultsIfEmpty();
        // Make the initialization metadata observably independent of the
        // account seed while keeping the production seeder responsible for
        // creating every default row.
        await source.customUpdate(
          'UPDATE categories SET created_at = ?, updated_at = ?',
          variables: [
            Variable<String>(DateTime.utc(2020, 1, 1).toIso8601String()),
            Variable<String>(DateTime.utc(2020, 1, 1).toIso8601String()),
          ],
          updates: {source.categories},
        );
        await _insertTask(
          source,
          id: '00000000-0000-7000-8000-000000000011',
          title: 'Offline task',
          clock: () => DateTime.utc(2026, 1, 1, 12),
        );
        return source;
      }

      try {
        final service = AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        );
        final first = await service.adopt();

        expect(first.copiedRecords, 1);
        expect((await account.select(account.tasks).get()), hasLength(2));
        expect(
          (await account.taskDao.getTaskById(destinationTask.id))?.title,
          'Existing account task',
        );
        final workId = CategoryRepository.defaultCategoryId('work');
        expect(
          (await account.categoryDao.getCategoryById(workId))?.name,
          'Work',
        );
        expect(
          (await account.select(account.categories).get()).where(
            (row) => row.id == workId,
          ),
          hasLength(1),
        );
        expect(
          (await account.taskDao.getTaskById(
            '00000000-0000-7000-8000-000000000011',
          ))?.categoryId,
          workId,
        );
        expect(
          (await account.select(account.categories).get()).map((row) => row.id),
          containsAll(
            CategoryRepository.defaultCategoryKeys.map(
              CategoryRepository.defaultCategoryId,
            ),
          ),
        );
        expect(await account.syncDao.pendingCount(), pendingBefore + 1);

        final second = await service.adopt();
        expect(second.copiedRecords, 0);
        expect((await account.select(account.tasks).get()), hasLength(2));
        expect((await account.select(account.categories).get()), hasLength(4));
        expect(await account.syncDao.pendingCount(), pendingBefore + 1);
      } finally {
        await account.close();
      }
    },
  );

  test('renamed built-in category remains an adoption conflict', () async {
    final account = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(account).seedDefaultsIfEmpty();

    Future<AppDatabase> sourceFactory() async {
      final source = AppDatabase(NativeDatabase.memory());
      final repository = CategoryRepository(source);
      await repository.seedDefaultsIfEmpty();
      final work = (await repository.getCategoryById(
        CategoryRepository.defaultCategoryId('work'),
      ))!;
      await repository.updateCategory(work.copyWith(name: 'Office'));
      return source;
    }

    try {
      await expectLater(
        AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        ).adopt(),
        throwsA(isA<AnonymousDataAdoptionException>()),
      );
      expect(
        (await account.categoryDao.getCategoryById(
          CategoryRepository.defaultCategoryId('work'),
        ))!.name,
        'Work',
      );
    } finally {
      await account.close();
    }
  });

  test(
    'deleted built-in category is not resurrected during adoption',
    () async {
      final account = AppDatabase(NativeDatabase.memory());
      await CategoryRepository(account).seedDefaultsIfEmpty();

      Future<AppDatabase> sourceFactory() async {
        final source = AppDatabase(NativeDatabase.memory());
        await CategoryRepository(source).seedDefaultsIfEmpty();
        await CategoryRepository(source)
            .deleteCategory(CategoryRepository.defaultCategoryId('work'));
        return source;
      }

      try {
        await expectLater(
          AnonymousDataAdoptionService(
            account,
            anonymousDatabaseFactory: sourceFactory,
          ).adopt(),
          throwsA(isA<AnonymousDataAdoptionException>()),
        );
        expect(
          (await account.categoryDao.getCategoryById(
            CategoryRepository.defaultCategoryId('work'),
          ))!.deletedAt,
          isNull,
        );
      } finally {
        await account.close();
      }
    },
  );

  test('changed built-in color is not treated as timestamp noise', () async {
    final account = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(account).seedDefaultsIfEmpty();

    Future<AppDatabase> sourceFactory() async {
      final source = AppDatabase(NativeDatabase.memory());
      final repository = CategoryRepository(source);
      await repository.seedDefaultsIfEmpty();
      final work = (await repository.getCategoryById(
        CategoryRepository.defaultCategoryId('work'),
      ))!;
      await repository.updateCategory(work.copyWith(colorHex: '#000000'));
      return source;
    }

    try {
      await expectLater(
        AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        ).adopt(),
        throwsA(isA<AnonymousDataAdoptionException>()),
      );
    } finally {
      await account.close();
    }
  });

  test('onboarding completion does not block local task adoption', () async {
    final account = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(account).seedDefaultsIfEmpty();
    await account.syncDao.setSetting(onboardingCompletedKey, 'false');

    Future<AppDatabase> sourceFactory() async {
      final source = AppDatabase(NativeDatabase.memory());
      await CategoryRepository(source).seedDefaultsIfEmpty();
      await source.syncDao.setSetting(onboardingCompletedKey, 'true');
      await _insertTask(
        source,
        id: '00000000-0000-7000-8000-000000000012',
        title: 'Onboarding task',
      );
      return source;
    }

    try {
      await AnonymousDataAdoptionService(
        account,
        anonymousDatabaseFactory: sourceFactory,
      ).adopt();
      expect(await account.syncDao.getSetting(onboardingCompletedKey), 'true');
      expect(
        (await account.taskDao.getTaskById(
          '00000000-0000-7000-8000-000000000012',
        ))?.title,
        'Onboarding task',
      );
    } finally {
      await account.close();
    }
  });

  test(
    'application failure rolls back the destination and remains retryable',
    () async {
      final account = AppDatabase(NativeDatabase.memory());

      Future<AppDatabase> sourceFactory() async {
        final source = AppDatabase(NativeDatabase.memory());
        // Build a deliberately invalid portable source row only for exercising
        // the transaction boundary; production repositories reject this FK.
        await source.customStatement('PRAGMA foreign_keys = OFF');
        await source
            .into(source.tasks)
            .insert(
              TasksCompanion.insert(
                id: '00000000-0000-7000-8000-000000000013',
                title: 'Orphan task',
                categoryId: const Value('00000000-0000-7000-8000-000000000099'),
                createdAt: DateTime.utc(2026, 1, 1),
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            );
        return source;
      }

      try {
        final service = AnonymousDataAdoptionService(
          account,
          anonymousDatabaseFactory: sourceFactory,
        );
        await expectLater(service.adopt(), throwsA(isA<Exception>()));
        expect(await account.select(account.tasks).get(), isEmpty);
        expect(await account.syncDao.pendingCount(), 0);

        await expectLater(service.adopt(), throwsA(isA<Exception>()));
        expect(await account.select(account.tasks).get(), isEmpty);
        expect(await account.syncDao.pendingCount(), 0);
      } finally {
        await account.close();
      }
    },
  );
}

Future<Task> _insertTask(
  AppDatabase database, {
  required String id,
  required String title,
  DateTime Function()? clock,
}) => TaskRepository(database, clock: clock).insertTask(
  Task(
    id: id,
    title: title,
    startTime: DateTime.utc(2026, 1, 2, 9),
    endTime: DateTime.utc(2026, 1, 2, 10),
    categoryId: CategoryRepository.defaultCategoryId('work'),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  ),
);
