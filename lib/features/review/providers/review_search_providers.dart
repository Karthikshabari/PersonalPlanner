import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/brief_keep_alive.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../settings/providers/week_start_provider.dart';
import '../domain/review_search.dart';

/// Every day and week Review search can find. Loaded only while Review search
/// shows results; re-read when tasks or reviews change.
final reviewSearchIndexProvider = StreamProvider.autoDispose<ReviewSearchIndex>(
  (ref) {
    keepAliveBriefly(ref);
    // Weeks are grouped by the week-start setting.
    ref.watch(weekStartDayProvider);
    final db = ref.watch(appDatabaseProvider);
    return watchReactiveStats(
      db,
      () => ReviewSearchIndexLoader(db).load(today: DateTime.now()),
      tables: [db.tasks, db.dailyReviews, db.weeklyReviews],
    );
  },
);
