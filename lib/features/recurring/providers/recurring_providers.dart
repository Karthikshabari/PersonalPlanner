import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/recurring_rule.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../data/recurring_repository.dart';
import '../domain/recurrence_service.dart';

final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  return RecurringRepository(ref.watch(appDatabaseProvider));
});

final recurrenceServiceProvider = Provider<RecurrenceService>((ref) {
  return RecurrenceService(ref.watch(appDatabaseProvider));
});

/// Single rule fetch for the editor.
final recurringRuleProvider = FutureProvider.autoDispose
    .family<RecurringRule?, String>((ref, ruleId) {
      return ref.watch(recurringRepositoryProvider).getRuleById(ruleId);
    });

/// Materializes the recurring rules for [date] when the Day View shows it
/// (planner.md Chunk 4 #3 "Trigger on day-view load"). autoDispose so a date
/// is re-materialized after rules change between visits; the service itself
/// skips dates that already have their instances.
final dayMaterializationProvider = FutureProvider.autoDispose
    .family<int, DateTime>((ref, date) {
      final normalized = startOfDay(date);
      return ref
          .watch(recurrenceServiceProvider)
          .materializeForDate(normalized);
    });
