import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';

/// Key used in the `app_settings` table for the first day of the week.
const String weekStartDaySettingKey = 'week_start_day';

/// The configured first day of the week (Monday by default). Loading or
/// changing it updates [plannerWeekStartDay] *before* dependents are notified,
/// so every `startOfWeek` call already sees the new value when they rebuild.
final weekStartDayProvider =
    AsyncNotifierProvider<WeekStartDayNotifier, WeekStartDay>(
      WeekStartDayNotifier.new,
    );

class WeekStartDayNotifier extends AsyncNotifier<WeekStartDay> {
  @override
  Future<WeekStartDay> build() async {
    final db = ref.watch(appDatabaseProvider);
    final value = WeekStartDay.parse(
      await db.syncDao.getSetting(weekStartDaySettingKey),
    );
    plannerWeekStartDay = value;
    return value;
  }

  Future<void> setWeekStart(WeekStartDay value) async {
    final previous = state.value ?? WeekStartDay.monday;
    plannerWeekStartDay = value;
    state = AsyncData(value);
    try {
      await ref
          .read(appDatabaseProvider)
          .syncDao
          .setSetting(weekStartDaySettingKey, value.name);
    } catch (_) {
      plannerWeekStartDay = previous;
      state = AsyncData(previous);
      rethrow;
    }
  }
}
