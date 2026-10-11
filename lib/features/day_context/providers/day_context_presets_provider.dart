import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../domain/break_day.dart';
import '../domain/day_context_presets.dart';
import 'day_context_providers.dart';

/// The "Day contexts" presets. Stored per device in `app_settings`; not
/// synced and not part of portable backup.
final dayContextPresetsProvider =
    AsyncNotifierProvider<DayContextPresetsNotifier, List<DayContextPreset>>(
      DayContextPresetsNotifier.new,
      // A failed read falls back to the defaults (see [readBreakDayRule]);
      // retrying would only repeat the failing read.
      retry: (retryCount, error) => null,
    );

class DayContextPresetsNotifier extends AsyncNotifier<List<DayContextPreset>> {
  @override
  Future<List<DayContextPreset>> build() async {
    final db = ref.watch(appDatabaseProvider);
    final raw = await db.syncDao.getSetting(dayContextPresetsSettingKey);
    return List.unmodifiable(DayContextPresets.decode(raw));
  }

  List<DayContextPreset> get _current =>
      state.value ?? defaultDayContextPresets;

  /// Returns the validation message, or null once added.
  Future<String?> add(String name) async {
    if (!DayContextPresets.canAdd(_current)) {
      return 'Maximum $maxDayContextPresets';
    }
    final error = DayContextPresets.validateName(_current, name);
    if (error != null) return error;
    await _write([..._current, DayContextPreset(name.trim())]);
    return null;
  }

  /// Returns the validation message, or null once renamed. Days already
  /// using the old name keep it.
  Future<String?> rename(int index, String name) async {
    if (index < 0 || index >= _current.length) return null;
    final error = DayContextPresets.validateName(
      _current,
      name,
      exceptIndex: index,
    );
    if (error != null) return error;
    await _write(
      [..._current]..[index] = _current[index].copyWith(name: name.trim()),
    );
    return null;
  }

  Future<void> setBreak(int index, bool isBreak) async {
    if (index < 0 || index >= _current.length) return;
    await _write(
      [..._current]..[index] = _current[index].copyWith(isBreak: isBreak),
    );
  }

  /// The last preset cannot be removed.
  Future<void> remove(int index) async {
    if (index < 0 || index >= _current.length || _current.length <= 1) return;
    await _write([..._current]..removeAt(index));
  }

  Future<void> resetToDefaults() => _write(List.of(defaultDayContextPresets));

  Future<void> _write(List<DayContextPreset> next) async {
    final previous = _current;
    state = AsyncData(List.unmodifiable(next));
    try {
      await ref
          .read(appDatabaseProvider)
          .syncDao
          .setSetting(
            dayContextPresetsSettingKey,
            DayContextPresets.encode(next),
          );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

/// The break-day rule from the current presets; the defaults while they
/// load. Dependents rebuild only when the set of break names changes.
final breakDayRuleProvider = Provider<BreakDayRule>((ref) {
  final presets = ref.watch(dayContextPresetsProvider).value;
  return presets == null ? BreakDayRule.defaults : BreakDayRule(presets);
});

/// The rule from the stored presets, not the defaults shown while they load
/// (the defaults when they cannot be read). For use inside a calculation that
/// is about to read the database.
Future<BreakDayRule> readBreakDayRule(Ref ref) async {
  try {
    return BreakDayRule(await ref.read(dayContextPresetsProvider.future));
  } catch (_) {
    return BreakDayRule.defaults;
  }
}

/// The break label of one planner date, or null when it is not a break day.
final breakLabelForDateProvider = Provider.autoDispose
    .family<String?, DateTime>((ref, date) {
      final context = ref.watch(dayContextForDateProvider(date)).value;
      return ref.watch(breakDayRuleProvider).breakLabel(context);
    });

/// Every break date (`yyyy-MM-dd` → label).
final breakDatesProvider = StreamProvider.autoDispose<Map<String, String>>((
  ref,
) {
  final rule = ref.watch(breakDayRuleProvider);
  return ref
      .watch(dayContextRepositoryProvider)
      .watchAll()
      .map(rule.breakDates);
});
