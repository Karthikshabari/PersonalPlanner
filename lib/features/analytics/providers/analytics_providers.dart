import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/analytics_models.dart';
import '../domain/analytics_service.dart';

final insightsNowProvider = Provider<DateTime>((ref) => DateTime.now());

final insightsServiceProvider = Provider<InsightsService>((ref) {
  return InsightsService(ref.watch(appDatabaseProvider));
});

final selectedInsightsWeekProvider = StateProvider<DateTime>((ref) {
  return startOfWeek(ref.watch(insightsNowProvider));
});

final insightsSnapshotProvider = StreamProvider.autoDispose<InsightsSnapshot>((
  ref,
) {
  final service = ref.watch(insightsServiceProvider);
  final weekStart = ref.watch(selectedInsightsWeekProvider);
  final now = ref.watch(insightsNowProvider);
  return watchReactiveStats(
    ref.read(appDatabaseProvider),
    () => service.compute(weekStart: weekStart, now: now),
  );
});

// Retained as a source-compatible invalidation hook for backup restore code.
final analyticsSnapshotProvider = insightsSnapshotProvider;
final analyticsProvider = insightsSnapshotProvider;
