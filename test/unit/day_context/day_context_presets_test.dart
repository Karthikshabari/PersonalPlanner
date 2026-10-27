import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/day_context/domain/day_context_presets.dart';
import 'package:personal_planner/features/day_context/providers/day_context_presets_provider.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('defaults', () {
    test('six presets in order, three of them breaks', () {
      expect(defaultDayContextPresets.map((p) => p.name), [
        'Office Day',
        'Work From Home',
        'Holiday / Festival',
        'Leave',
        'Travel',
        'Rest Day',
      ]);
      expect(
        defaultDayContextPresets.where((p) => p.isBreak).map((p) => p.name),
        ['Holiday / Festival', 'Leave', 'Rest Day'],
      );
    });

    test('absent or invalid storage gives the defaults', () {
      expect(DayContextPresets.decode(null), defaultDayContextPresets);
      expect(DayContextPresets.decode('not json'), defaultDayContextPresets);
      expect(DayContextPresets.decode('[]'), defaultDayContextPresets);
    });

    test('encode and decode round trip', () {
      const presets = [
        DayContextPreset('Gym day'),
        DayContextPreset('Sick', isBreak: true),
      ];
      expect(
        DayContextPresets.decode(DayContextPresets.encode(presets)),
        presets,
      );
    });
  });

  group('validation', () {
    test('an empty name is refused', () {
      expect(
        DayContextPresets.validateName(defaultDayContextPresets, '   '),
        'Enter a name',
      );
    });

    test('a name longer than 24 characters is refused', () {
      expect(
        DayContextPresets.validateName(defaultDayContextPresets, 'x' * 25),
        'Use 24 characters or fewer',
      );
      expect(
        DayContextPresets.validateName(defaultDayContextPresets, 'x' * 24),
        isNull,
      );
    });

    test('the limit counts visible characters, not UTF-16 units', () {
      // 21 letters + 3 emoji = 24 visible characters, 27 UTF-16 units.
      final fits = '${'x' * 21}\u{1F600}\u{1F600}\u{1F600}';
      expect(fits.length, 27);
      expect(
        DayContextPresets.validateName(defaultDayContextPresets, fits),
        isNull,
      );
      expect(
        DayContextPresets.validateName(defaultDayContextPresets, '${fits}x'),
        'Use 24 characters or fewer',
      );
    });

    test('duplicates are refused ignoring case and spaces', () {
      for (final name in ['leave', 'LEAVE', ' Leave ', 'Rest day', 'restday']) {
        expect(
          DayContextPresets.validateName(defaultDayContextPresets, name),
          'Already in the list',
          reason: name,
        );
      }
    });

    test('renaming a preset may keep its own name', () {
      final index = defaultDayContextPresets.indexWhere(
        (p) => p.name == 'Leave',
      );
      expect(
        DayContextPresets.validateName(
          defaultDayContextPresets,
          'leave',
          exceptIndex: index,
        ),
        isNull,
      );
    });

    test('at most 8 presets', () {
      final eight = [
        ...defaultDayContextPresets,
        const DayContextPreset('Seven'),
        const DayContextPreset('Eight'),
      ];
      expect(DayContextPresets.canAdd(defaultDayContextPresets), isTrue);
      expect(DayContextPresets.canAdd(eight), isFalse);
      final stored = DayContextPresets.encode([
        ...eight,
        const DayContextPreset('Nine'),
      ]);
      expect(DayContextPresets.decode(stored), eight);
    });

    test('decode drops blank, too long and duplicate entries', () {
      final decoded = DayContextPresets.decode(
        '[{"name":"Gym","break":false},{"name":" "},'
        '{"name":"${'y' * 30}"},{"name":"gym","break":true}]',
      );
      expect(decoded, const [DayContextPreset('Gym')]);
    });
  });

  test('a built-in kind label saves as that kind, anything else as custom', () {
    expect(DayContextPresets.kindForName('Leave'), DayContextKind.leave);
    expect(
      DayContextPresets.kindForName('holiday / festival'),
      DayContextKind.holiday,
    );
    expect(DayContextPresets.kindForName('Office Day'), DayContextKind.office);
    expect(
      DayContextPresets.kindForName('Work From Home'),
      DayContextKind.custom,
    );
    expect(DayContextPresets.kindForName('Custom'), DayContextKind.custom);
  });

  group('pastDayCountForPreset', () {
    late AppDatabase db;
    late ProviderContainer container;
    late DayContextRepository repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      repository = DayContextRepository(db);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> count(String name) => container
        .read(dayContextPresetsProvider.notifier)
        .pastDayCountForPreset(name);

    test('matches labels ignoring case and spaces', () async {
      await repository.save('2026-09-01', DayContextKind.leave, null);
      await repository.save(
        '2026-09-02',
        DayContextKind.custom,
        '  rest  DAY ',
      );
      await repository.save('2026-09-03', DayContextKind.custom, 'Sabbatical');
      expect(await count('LEAVE'), 1);
      expect(await count('Rest Day'), 1);
      expect(await count('restday'), 1);
      expect(await count('Never used'), 0);
    });

    test('ignores soft-deleted days', () async {
      final day = await repository.save(
        '2026-09-01',
        DayContextKind.leave,
        null,
      );
      await repository.save('2026-09-02', DayContextKind.leave, null);
      expect(await count('Leave'), 2);
      await repository.remove(day.id, expectedRevision: day.revision);
      expect(await count('Leave'), 1);
    });
  });
}
