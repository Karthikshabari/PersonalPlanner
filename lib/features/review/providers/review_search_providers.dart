import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/brief_keep_alive.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../../analytics/providers/analytics_providers.dart';
import '../../settings/providers/week_start_provider.dart';
import '../domain/review_search.dart';

/// Every day and week Review search can find. Loaded only while Review search
/// shows results; re-read when tasks or reviews change, and when the planner
/// day rolls over (the Insights midnight and resume clock, which also drives
/// the Day selection rollover).
final reviewSearchIndexProvider = StreamProvider.autoDispose<ReviewSearchIndex>(
  (ref) {
    keepAliveBriefly(ref);
    // Weeks are grouped by the week-start setting.
    ref.watch(weekStartDayProvider);
    // Selected down to the day, so the clock's other events change nothing.
    final today = ref.watch(insightsNowProvider.select(startOfDay));
    final db = ref.watch(appDatabaseProvider);
    return watchReactiveStats(
      db,
      () => ReviewSearchIndexLoader(db).load(today: today),
      tables: [db.tasks, db.dailyReviews, db.weeklyReviews],
    );
  },
);
