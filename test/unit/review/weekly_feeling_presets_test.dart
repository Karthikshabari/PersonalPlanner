import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/review/domain/weekly_feeling_presets.dart';
import 'package:personal_planner/features/review/providers/weekly_feeling_presets_provider.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('WeeklyFeelingPresets', () {
    test('absent or invalid storage yields the defaults', () {
      expect(WeeklyFeelingPresets.decode(null), defaultWeeklyFeelingPresets);
      expect(WeeklyFeelingPresets.decode('nope'), defaultWeeklyFeelingPresets);
      expect(WeeklyFeelingPresets.decode('{}'), defaultWeeklyFeelingPresets);
    });

    test('unset, blank, long and duplicate slots fall back per slot', () {
      expect(
        WeeklyFeelingPresets.decode(
          WeeklyFeelingPresets.encode(['Joyful', ' ', 'x' * 15, 'joyful']),
        ),
        ['Joyful', 'Calm', 'Tired', 'Proud'],
      );
      expect(WeeklyFeelingPresets.decode('["Joyful"]'), [
        'Joyful',
        'Calm',
        'Tired',
        'Proud',
      ]);
    });

    test('a default already taken by another slot is not repeated', () {
      final decoded = WeeklyFeelingPresets.decode('["Calm","","",""]');
      expect(decoded, hasLength(4));
      expect(decoded.map((e) => e.toLowerCase()).toSet(), hasLength(4));
    });

    test('validate rejects blank, long and duplicate labels', () {
      const presets = ['Focused', 'Calm', 'Tired', 'Proud'];
      expect(WeeklyFeelingPresets.validate(presets, 0, '  '), isNotNull);
      expect(WeeklyFeelingPresets.validate(presets, 0, 'x' * 15), isNotNull);
      expect(WeeklyFeelingPresets.validate(presets, 0, ' calm '), isNotNull);
      expect(WeeklyFeelingPresets.validate(presets, 1, 'Calm'), isNull);
      expect(WeeklyFeelingPresets.validate(presets, 0, 'x' * 14), isNull);
    });
  });

  group('WeeklyFeelingPresetsNotifier', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer newContainer() {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('setAt persists, invalid text is refused, reset restores', () async {
      final first = newContainer();
      expect(
        await first.read(weeklyFeelingPresetsProvider.future),
        defaultWeeklyFeelingPresets,
      );
      final notifier = first.read(weeklyFeelingPresetsProvider.notifier);
      expect(await notifier.setAt(1, ' Joyful '), isTrue);
      expect(await notifier.setAt(2, 'Proud'), isFalse);
      expect(await notifier.setAt(2, ''), isFalse);

      final second = newContainer();
      expect(await second.read(weeklyFeelingPresetsProvider.future), [
        'Focused',
        'Joyful',
        'Tired',
        'Proud',
      ]);

      await second
          .read(weeklyFeelingPresetsProvider.notifier)
          .resetToDefaults();
      expect(
        await newContainer().read(weeklyFeelingPresetsProvider.future),
        defaultWeeklyFeelingPresets,
      );
    });
  });
}
