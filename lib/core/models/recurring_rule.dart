import 'package:freezed_annotation/freezed_annotation.dart';

part 'recurring_rule.freezed.dart';
part 'recurring_rule.g.dart';

/// A recurring-task rule. [rrule] holds the RFC 5545 string without the
/// `RRULE:` prefix (e.g. `FREQ=WEEKLY;BYDAY=MO,WE`), matching the examples
/// in architecture.md §8.
@freezed
abstract class RecurringRule with _$RecurringRule {
  const factory RecurringRule({
    required String id,
    required String rrule,
    required String taskTitle,
    String? taskDescription,
    required int durationMin,
    String? categoryId,
    @Default(0) int priority,
    @Default([]) List<String> tags,
    /// Local wall-clock time of day as `HH:mm`.
    required String startTimeOfDay,
    /// First date the rule can occur on (`yyyy-MM-dd`).
    required DateTime startDate,
    DateTime? endDate,
    @Default(true) bool isActive,
    /// Excluded dates as `yyyy-MM-dd` strings.
    @Default([]) List<String> exceptions,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _RecurringRule;

  factory RecurringRule.fromJson(Map<String, dynamic> json) =>
      _$RecurringRuleFromJson(json);
}
