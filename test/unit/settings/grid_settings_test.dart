import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/grid_settings_provider.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  // Real async zone (no FakeAsync): safe to close Drift explicitly here.
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    setupSqliteForTests();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('GridIntervalNotifier persistence', () {
    test('defaults to 60 when nothing stored', () async {
      final value = await container.read(gridIntervalProvider.future);
      expect(value, 60);
    });

    test('loads a stored interval from app_settings', () async {
      await db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?)',
        [gridIntervalSettingKey, '15'],
      );
      final value = await container.read(gridIntervalProvider.future);
      expect(value, 15);
    });

    test('setInterval writes app_settings row (upsert)', () async {
      await container.read(gridIntervalProvider.future);
      await container.read(gridIntervalProvider.notifier).setInterval(30);

      final rows = await (db.select(db.appSettings)
            ..where((s) => s.key.equals(gridIntervalSettingKey)))
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.value, '30');

      // Changing again updates instead of duplicating.
      await container.read(gridIntervalProvider.notifier).setInterval(60);
      final rows2 = await (db.select(db.appSettings)
            ..where((s) => s.key.equals(gridIntervalSettingKey)))
          .get();
      expect(rows2, hasLength(1));
      expect(rows2.single.value, '60');
    });

    test('rejects values outside 15/30/60 and stores default', () async {
      await container.read(gridIntervalProvider.future);
      await container.read(gridIntervalProvider.notifier).setInterval(45);
      expect(await container.read(gridIntervalProvider.future), 60);
    });
  });
}
