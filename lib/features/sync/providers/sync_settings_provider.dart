import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';

const syncEnabledKey = 'sync.enabled';

final syncEnabledProvider = AsyncNotifierProvider<SyncEnabledNotifier, bool>(
  SyncEnabledNotifier.new,
);

class SyncEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row =
        await (db.select(db.appSettings)
              ..where((setting) => setting.key.equals(syncEnabledKey)))
            .getSingleOrNull();
    return row?.value != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state.value ?? true;
    state = AsyncData(enabled);
    try {
      final db = ref.read(appDatabaseProvider);
      await db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [syncEnabledKey, '$enabled'],
      );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
