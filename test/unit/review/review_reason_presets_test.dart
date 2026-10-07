import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/review/domain/review_reason_presets.dart';
import 'package:personal_planner/features/review/providers/review_reason_presets_provider.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('ReviewReasonPresets', () {
    test('decode falls back to defaults for absent or invalid storage', () {
      expect(ReviewReasonPresets.decode(null), defaultReviewReasonPresets);
      expect(
        ReviewReasonPresets.decode('not json'),
        defaultReviewReasonPresets,
      );
    });

    test('decode keeps a stored empty list empty', () {
      expect(ReviewReasonPresets.decode('[]'), isEmpty);
    });

    test('decode truncates a 40-character entry to 28 characters', () {
      final decoded = ReviewReasonPresets.decode(
        ReviewReasonPresets.encode(['a' * 40]),
      );
      expect(decoded.single, 'a' * 28);
    });

    test('canSaveAsPreset rejects blank, long, duplicate and full lists', () {
      const presets = ['Blocked', 'Interrupted'];
      expect(ReviewReasonPresets.canSaveAsPreset(presets, '   '), isFalse);
      expect(ReviewReasonPresets.canSaveAsPreset(presets, 'a' * 29), isFalse);
      expect(ReviewReasonPresets.canSaveAsPreset(presets, 'blocked'), isFalse);
      expect(
        ReviewReasonPresets.canSaveAsPreset(const [
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
        ], 'g'),
        isFalse,
      );
      expect(
        ReviewReasonPresets.canSaveAsPreset(presets, 'Meeting ran long'),
        isTrue,
      );
    });

    test('withSaved fills a blank slot first', () {
      expect(ReviewReasonPresets.withSaved(const ['a', '', 'c'], ' b '), [
        'a',
        'b',
        'c',
      ]);
      expect(ReviewReasonPresets.withSaved(const ['a'], 'b'), ['a', 'b']);
    });
  });

  group('ReviewReasonPresetsNotifier', () {
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

    test('saveAsPreset persists and resetToDefaults restores', () async {
      final first = newContainer();
      expect(
        await first.read(reviewReasonPresetsProvider.future),
        defaultReviewReasonPresets,
      );
      final notifier = first.read(reviewReasonPresetsProvider.notifier);
      expect(await notifier.saveAsPreset('Meeting ran long'), isTrue);

      final second = newContainer();
      final reloaded = await second.read(reviewReasonPresetsProvider.future);
      expect(reloaded, hasLength(6));
      expect(reloaded.last, 'Meeting ran long');

      await second.read(reviewReasonPresetsProvider.notifier).resetToDefaults();
      final third = newContainer();
      expect(
        await third.read(reviewReasonPresetsProvider.future),
        defaultReviewReasonPresets,
      );
    });
  });
}
