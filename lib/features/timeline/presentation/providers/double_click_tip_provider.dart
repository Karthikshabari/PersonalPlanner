import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';

/// Per-device flag (`app_settings`, not synced) set once the user dismisses the
/// "double-click an empty slot" tip.
const String dayCreateTipDismissedSettingKey = 'day_create_tip_dismissed';

/// "double-click" on desktop, "double-tap" on touch platforms.
String doubleClickVerb() =>
    defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS
    ? 'double-tap'
    : 'double-click';

final dayCreateTipDismissedProvider =
    AsyncNotifierProvider<DayCreateTipDismissedNotifier, bool>(
      DayCreateTipDismissedNotifier.new,
    );

class DayCreateTipDismissedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row =
        await (db.select(db.appSettings)
              ..where((s) => s.key.equals(dayCreateTipDismissedSettingKey)))
            .getSingleOrNull();
    return row?.value == '1';
  }

  Future<void> dismiss() async {
    state = const AsyncData(true);
    final db = ref.read(appDatabaseProvider);
    await db.customStatement(
      'INSERT INTO app_settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [dayCreateTipDismissedSettingKey, '1'],
    );
  }
}
