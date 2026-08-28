import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/settings/providers/notification_settings_providers.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('nextOccurrence', () {
    test('returns today when the time is still ahead', () {
      final now = DateTime(2026, 8, 25, 10);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 25, 21),
      );
    });

    test('rolls over to tomorrow once the time has passed', () {
      final now = DateTime(2026, 8, 25, 22, 30);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 26, 21),
      );
    });

    test('exact match rolls over (must be strictly in the future)', () {
      final now = DateTime(2026, 8, 25, 21);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 26, 21),
      );
    });
  });

  group('reminder settings persistence', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<String?> setting(String key) async {
      final row = await (db.select(db.appSettings)
            ..where((s) => s.key.equals(key)))
          .getSingleOrNull();
      return row?.value;
    }

    test('defaults are enabled at 21:00', () async {
      expect(await container.read(reviewReminderEnabledProvider.future), isTrue);
      expect(
          await container.read(reviewReminderMinutesProvider.future),
          defaultReminderMinutes);
    });

    test('toggle persists to app_settings', () async {
      await container.read(reviewReminderEnabledProvider.notifier).setEnabled(false);
      expect(await setting(reminderEnabledKey), 'false');

      await container.read(reviewReminderEnabledProvider.notifier).setEnabled(true);
      expect(await setting(reminderEnabledKey), 'true');
    });

    test('time persists and re-reads', () async {
      await container
          .read(reviewReminderMinutesProvider.notifier)
          .setMinutes(8 * 60 + 35);
      expect(await setting(reminderTimeKey), '515');
      expect(
          await container.read(reviewReminderMinutesProvider.future), 515);
    });

    test('invalid stored time falls back to the default', () async {
      await db.into(db.appSettings).insert(AppSettingsCompanion.insert(
            key: reminderTimeKey,
            value: '99999',
          ));
      expect(
          await container.read(reviewReminderMinutesProvider.future),
          defaultReminderMinutes);
    });
  });
}
