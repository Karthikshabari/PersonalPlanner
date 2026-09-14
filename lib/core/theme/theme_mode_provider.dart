import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';

/// The persisted appearance preference. An absent preference intentionally
/// resolves to dark to preserve the product default; selecting System is an
/// explicit user choice and is stored separately.
const String themeModeSettingKey = 'theme_mode';

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row =
        await (db.select(db.appSettings)
              ..where((setting) => setting.key.equals(themeModeSettingKey)))
            .getSingleOrNull();
    return _parse(row?.value) ?? ThemeMode.dark;
  }

  Future<void> setMode(ThemeMode mode) async {
    final previous = state.value ?? ThemeMode.dark;
    state = AsyncData(mode);
    try {
      final db = ref.read(appDatabaseProvider);
      await db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [themeModeSettingKey, mode.name],
      );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  static ThemeMode? _parse(String? value) => switch (value) {
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => null,
  };
}
