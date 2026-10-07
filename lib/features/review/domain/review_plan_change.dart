import '../../../core/models/task.dart';

/// The kinds of plan change the app records. Only title changes are
/// persisted today (`tasks.plan_title_history_json`).
enum ReviewPlanChangeKind { title }

/// One plan change shown by the review for a task.
class ReviewPlanChange {
  final ReviewPlanChangeKind kind;
  final String oldValue;
  final String newValue;

  /// Optional text typed in the plan-change dialog. Null when none.
  final String? reason;

  const ReviewPlanChange({
    required this.kind,
    required this.oldValue,
    required this.newValue,
    this.reason,
  });

  /// The selected, non-reverted title change for [task], the same event the
  /// Day timeline decorates. Null when the task has none.
  static ReviewPlanChange? forTask(Task task) {
    final event = task.displayPlanChange;
    if (event == null) return null;
    return ReviewPlanChange(
      kind: ReviewPlanChangeKind.title,
      oldValue: event.previousTitle,
      newValue: event.newTitle,
    );
  }
}
