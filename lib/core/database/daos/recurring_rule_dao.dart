import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/recurring_rules_table.dart';

part 'recurring_rule_dao.g.dart';

@DriftAccessor(tables: [RecurringRules])
class RecurringRuleDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringRuleDaoMixin {
  RecurringRuleDao(super.db);

  /// All active (non-deleted) rules, regardless of [RecurringRules.isActive];
  /// deactivation is expressed via the flag so history stays queryable.
  Stream<List<RecurringRuleRow>> watchActiveRules() {
    return (select(recurringRules)
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.startDate)]))
        .watch();
  }

  Future<List<RecurringRuleRow>> getActiveRules() =>
      (select(recurringRules)..where((r) => r.deletedAt.isNull()))
          .get();

  Future<RecurringRuleRow?> getRuleById(String id) =>
      (select(recurringRules)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertRule(RecurringRulesCompanion entry) =>
      into(recurringRules).insert(entry);

  Future<bool> updateRule(RecurringRuleRow row) =>
      update(recurringRules).replace(row);

  Future<int> softDeleteRule(String id, DateTime deletedAt) async {
    final current = await getRuleById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(
        deletedAt: Value(deletedAt),
        isActive: const Value(false),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }

  /// Tasks materialized from a rule on one specific day (local calendar day,
  /// stored as UTC ISO timestamps — same convention as TaskDao).
  Future<List<TaskRow>> getInstancesForDay(String ruleId, String dayStartUtcIso, String nextDayStartUtcIso) {
    return (select(db.tasks)
          ..where((t) =>
              t.recurringRuleId.equals(ruleId) &
              t.deletedAt.isNull() &
              t.startTime.isBiggerOrEqualValue(dayStartUtcIso) &
              t.startTime.isSmallerThanValue(nextDayStartUtcIso)))
        .get();
  }
}
