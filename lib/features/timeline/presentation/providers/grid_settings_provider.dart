import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/database_provider.dart';

/// Key used in the `app_settings` table for the snap-to-grid interval.
const String gridIntervalSettingKey = 'grid_interval_minutes';

/// The configured grid interval in minutes (15 / 30 / 60, default 60),
/// loaded from `app_settings` and persisted on change. Watching this provider
/// immediately re-renders the timeline when the setting changes.
final gridIntervalProvider =
    AsyncNotifierProvider<GridIntervalNotifier, int>(
  GridIntervalNotifier.new,
);

class GridIntervalNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(gridIntervalSettingKey)))
        .getSingleOrNull();
    final value = int.tryParse(row?.value ?? '');
    if (value != null && AppConstants.gridOptions.contains(value)) {
      return value;
    }
    return AppConstants.defaultGridMinutes;
  }

  Future<void> setInterval(int minutes) async {
    final effective = AppConstants.gridOptions.contains(minutes)
        ? minutes
        : AppConstants.defaultGridMinutes;
    state = AsyncData(effective);
    final db = ref.watch(appDatabaseProvider);
    await db.customStatement(
      'INSERT INTO app_settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [gridIntervalSettingKey, '$effective'],
    );
  }
}
