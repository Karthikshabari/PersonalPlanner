import 'enums/task_status.dart';

/// The one rule for which blocks count in a day's or week's plan.
///
/// A block rescheduled to a new block that still exists was replaced: the new
/// block is the plan, so the old one adds neither a task nor planned minutes.
/// When the new block is gone (deleted, or its row is missing) the old block
/// counts again. Whether the new block is live is a fact the data code
/// supplies ([successorLive]); this rule never reads the database.
bool isReplacedByReschedule(
  TaskStatus status,
  String? rescheduledToId, {
  required bool successorLive,
}) =>
    status == TaskStatus.rescheduled &&
    rescheduledToId != null &&
    successorLive;

/// Counts as a task of its day (total, "x of y"). Cancelled still counts.
bool countsAsPlannedTask(
  TaskStatus status,
  String? rescheduledToId, {
  required bool successorLive,
}) => !isReplacedByReschedule(
  status,
  rescheduledToId,
  successorLive: successorLive,
);

/// Counts towards planned minutes. Cancelled does not; Skipped does.
bool countsAsPlannedTime(
  TaskStatus status,
  String? rescheduledToId, {
  required bool successorLive,
}) =>
    status != TaskStatus.cancelled &&
    countsAsPlannedTask(status, rescheduledToId, successorLive: successorLive);
