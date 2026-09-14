import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  late AppDatabase db;
  late DayContextRepository repository;

  setUp(() {
    setupSqliteForTests();
    db = AppDatabase(NativeDatabase.memory());
    repository = DayContextRepository(db);
  });

  tearDown(() => db.close());

  test('saves, watches, removes, and restores one date identity', () async {
    final saved = await repository.save(
      '2026-09-18',
      DayContextKind.travel,
      null,
    );
    final expectedId = generateDeterministicUuid('day-context:2026-09-18');
    expect(saved.id, expectedId);
    expect(saved.revision, 1);
    expect(await repository.watchForDate('2026-09-18').first, equals(saved));

    await repository.remove(saved.id, expectedRevision: saved.revision);
    expect(await repository.watchForDate('2026-09-18').first, isNull);
    final tombstone = await (db.select(
      db.dayContexts,
    )..where((row) => row.id.equals(saved.id))).getSingle();
    expect(tombstone.deletedAt, isNotNull);
    expect(tombstone.revision, 2);

    final restored = await repository.save(
      '2026-09-18',
      DayContextKind.custom,
      '  Family visit  ',
      expectedRevision: 2,
    );
    expect(restored.id, saved.id);
    expect(restored.revision, 3);
    expect(restored.customLabel, 'Family visit');
    expect((await repository.watchForDate('2026-09-18').first)!.id, saved.id);
  });

  test('strictly validates real dates and custom labels', () async {
    expect(
      () => repository.save('2026-9-18', DayContextKind.office, null),
      throwsArgumentError,
    );
    expect(
      () => repository.save('2026-02-30', DayContextKind.office, null),
      throwsArgumentError,
    );
    expect(
      () => repository.save('2026-09-18', DayContextKind.custom, '   '),
      throwsArgumentError,
    );
    expect(
      () => repository.save(
        '2026-09-18',
        DayContextKind.custom,
        List.filled(81, 'x').join(),
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.save('2026-09-18', DayContextKind.travel, 'Trip'),
      throwsArgumentError,
    );
  });

  test('range watch returns active contexts in calendar order', () async {
    await repository.save('2026-09-20', DayContextKind.leave, null);
    await repository.save('2026-09-18', DayContextKind.holiday, null);
    await repository.save('2026-09-19', DayContextKind.custom, 'Family');
    final contexts = await repository
        .watchRange('2026-09-18', '2026-09-21')
        .first;

    expect(contexts.map((context) => context.date), [
      '2026-09-18',
      '2026-09-19',
      '2026-09-20',
    ]);
  });

  test('revision CAS rejects stale edits without touching tasks', () async {
    final first = await repository.save(
      '2026-09-18',
      DayContextKind.office,
      null,
    );
    final second = await repository.save(
      '2026-09-18',
      DayContextKind.leave,
      null,
      expectedRevision: first.revision,
    );

    expect(
      repository.save(
        '2026-09-18',
        DayContextKind.travel,
        null,
        expectedRevision: first.revision,
      ),
      throwsA(isA<DayContextConflictException>()),
    );
    expect(
      repository.remove(first.id, expectedRevision: first.revision),
      throwsA(isA<DayContextConflictException>()),
    );
    expect(
      (await repository.watchForDate('2026-09-18').first)!.kind,
      second.kind,
    );
    expect(await db.select(db.tasks).get(), isEmpty);
    final operations = await db.syncDao.getActiveOperationsForRecord(
      'day_contexts',
      first.id,
    );
    expect(operations, hasLength(2));
    expect(
      operations.where((operation) => operation.entityTableName == 'tasks'),
      isEmpty,
    );
  });
}
