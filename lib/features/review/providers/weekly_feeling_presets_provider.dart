import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../domain/weekly_feeling_presets.dart';

/// The four feeling words under "How did the week feel?". Stored per device
/// in `app_settings`; not synced and not part of portable backup.
final weeklyFeelingPresetsProvider =
    AsyncNotifierProvider<WeeklyFeelingPresetsNotifier, List<String>>(
      WeeklyFeelingPresetsNotifier.new,
    );

class WeeklyFeelingPresetsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final db = ref.watch(appDatabaseProvider);
    final raw = await db.syncDao.getSetting(weeklyFeelingPresetsSettingKey);
    return List.unmodifiable(WeeklyFeelingPresets.decode(raw));
  }

  List<String> get _current => state.value ?? defaultWeeklyFeelingPresets;

  /// Returns false (and stores nothing) when [text] is not valid for the slot.
  Future<bool> setAt(int index, String text) async {
    if (index < 0 || index >= weeklyFeelingPresetCount) return false;
    if (WeeklyFeelingPresets.validate(_current, index, text) != null) {
      return false;
    }
    await _write([..._current]..[index] = text.trim());
    return true;
  }

  Future<void> resetToDefaults() =>
      _write(List.of(defaultWeeklyFeelingPresets));

  Future<void> _write(List<String> next) async {
    final previous = _current;
    state = AsyncData(List.unmodifiable(next));
    try {
      await ref
          .read(appDatabaseProvider)
          .syncDao
          .setSetting(
            weeklyFeelingPresetsSettingKey,
            WeeklyFeelingPresets.encode(next),
          );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
