import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/day_context.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../data/day_context_repository.dart';

final dayContextRepositoryProvider = Provider<DayContextRepository>((ref) {
  return DayContextRepository(ref.watch(appDatabaseProvider));
});

/// Active context for a planner date. The family takes DateTime to match the
/// existing Day/Week date providers, then converts only to canonical date text.
final dayContextForDateProvider = StreamProvider.autoDispose
    .family<DayContext?, DateTime>((ref, date) {
      return ref
          .watch(dayContextRepositoryProvider)
          .watchForDate(isoDateString(date));
    });

class DayContextRange {
  final String startInclusive;
  final String endExclusive;

  const DayContextRange(this.startInclusive, this.endExclusive);

  @override
  bool operator ==(Object other) =>
      other is DayContextRange &&
      other.startInclusive == startInclusive &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(startInclusive, endExclusive);
}

final dayContextsRangeProvider = StreamProvider.autoDispose
    .family<List<DayContext>, DayContextRange>((ref, range) {
      return ref
          .watch(dayContextRepositoryProvider)
          .watchRange(range.startInclusive, range.endExclusive);
    });
