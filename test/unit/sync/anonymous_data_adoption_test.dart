import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/sync/data/anonymous_data_adoption.dart';

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
}
