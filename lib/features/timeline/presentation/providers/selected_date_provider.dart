import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../analytics/providers/analytics_providers.dart';

final selectedDateProvider = StateProvider<DateTime>((ref) {
  return startOfDay(DateTime.now());
});

/// Moves the Day selection to the new today when the planner calendar day
/// changes, but only if the selection was the previous today. A deliberately
/// browsed date is left alone. Uses the Insights midnight/resume clock.
/// Must be watched by a long-lived widget to stay active.
final selectedDateRolloverProvider = Provider.autoDispose<void>((ref) {
  final now = ref.watch(insightsNowFactoryProvider);
  var lastToday = startOfDay(now());
  final subscription = ref.watch(insightsClockFactoryProvider)().listen((
    instant,
  ) {
    final today = startOfDay(instant);
    if (today == lastToday) return;
    final selected = ref.read(selectedDateProvider);
    if (selected == lastToday) {
      ref.read(selectedDateProvider.notifier).state = today;
    }
    lastToday = today;
  });
  ref.onDispose(subscription.cancel);
});
