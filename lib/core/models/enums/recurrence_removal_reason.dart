/// Persisted provenance for recurrence-owned task tombstones.
abstract final class RecurrenceRemovalReason {
  static const ruleExcluded = 'rule_excluded';
  static const values = {ruleExcluded};
}
