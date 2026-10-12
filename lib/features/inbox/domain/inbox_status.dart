import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/models/enums/task_status.dart';
import '../../../core/models/inbox_closure.dart';
import 'inbox_history.dart';

part 'inbox_status.freezed.dart';

/// What happened to one planned session of an Inbox idea. Derived from the
/// session's Day task every time it is needed; never stored.
enum InboxSessionStatus { upcoming, missed, done, carried, skipped, dropped }

/// Where an Inbox idea stands. Derived, never stored.
enum InboxItemStatus { idea, soon, left, finished, closed }

/// The few task columns a session status needs. Built from a light SQL row.
@freezed
abstract class InboxSessionFacts with _$InboxSessionFacts {
  const factory InboxSessionFacts({
    required String id,
    required String itemId,
    required String title,
    DateTime? start,
    DateTime? end,
    required TaskStatus status,
    DateTime? deletedAt,
    required DateTime createdAt,
  }) = _InboxSessionFacts;
}

/// The few columns of an Inbox idea an item status needs.
@freezed
abstract class InboxItemFacts with _$InboxItemFacts {
  const factory InboxItemFacts({
    required String id,

    /// The raw description.
    required String text,
    required DateTime createdAt,

    /// Legacy hint only.
    String? dueDate,
    @Default(<InboxClosure>[]) List<InboxClosure> history,
  }) = _InboxItemFacts;
}

/// First matching row wins (plan section 5). A session ends the moment its
/// end time is reached: `end == now` is already missed.
InboxSessionStatus sessionStatusOf(InboxSessionFacts session, DateTime now) {
  final start = session.start;
  final end = session.end;
  if (session.deletedAt != null || start == null || end == null) {
    return InboxSessionStatus.dropped;
  }
  return switch (session.status) {
    TaskStatus.completed => InboxSessionStatus.done,
    TaskStatus.rescheduled => InboxSessionStatus.carried,
    TaskStatus.skipped || TaskStatus.cancelled => InboxSessionStatus.skipped,
    TaskStatus.planned || TaskStatus.inProgress =>
      end.isAfter(now)
          ? InboxSessionStatus.upcoming
          : InboxSessionStatus.missed,
  };
}

/// First matching row wins (plan section 5). [sessions] are the sessions of
/// [item] only, deleted ones included; the caller groups them by item.
InboxItemStatus itemStatusOf(
  InboxItemFacts item,
  Iterable<InboxSessionFacts> sessions,
  DateTime now,
) {
  if (InboxHistory.isClosed(item.history)) return InboxItemStatus.closed;
  final reopenedAt = InboxHistory.lastReopenedAt(item.history);
  var anyMissed = false;
  var anyFinished = false;
  for (final session in sessions) {
    switch (sessionStatusOf(session, now)) {
      case InboxSessionStatus.upcoming:
        return InboxItemStatus.soon;
      case InboxSessionStatus.missed:
        anyMissed = true;
      case InboxSessionStatus.done:
        if (reopenedAt == null || session.createdAt.isAfter(reopenedAt)) {
          anyFinished = true;
        }
      case InboxSessionStatus.carried:
      case InboxSessionStatus.skipped:
      case InboxSessionStatus.dropped:
        break;
    }
  }
  if (anyMissed) return InboxItemStatus.left;
  if (anyFinished) return InboxItemStatus.finished;
  return InboxItemStatus.idea;
}
