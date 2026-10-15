import '../../../../../core/models/inbox_item.dart';
import '../../../../../core/utils/planner_time_zone.dart';

/// The groups of the Day attention list, in display order: what can still be
/// acted on first (Due today, then tasks that slipped Today and Yesterday),
/// with the long tail of Earlier rows last so it does not push them below the
/// fold. Rows inside a group are oldest first. This is a display order only:
/// "Move all to today" uses [overdueOldestFirst], not this order.
enum AttentionGroupKind {
  dueToday('Due today'),
  today('Today'),
  yesterday('Yesterday'),
  earlier('Earlier');

  const AttentionGroupKind(this.label);

  final String label;
}

class AttentionGroup {
  const AttentionGroup(this.kind, this.items);

  final AttentionGroupKind kind;

  /// Oldest first.
  final List<InboxItem> items;

  String get label => kind.label;
}

/// Splits [items] into "Due today" (explicit Inbox captures) and the overdue
/// groups Earlier, Yesterday and Today, by the planner-local calendar date of
/// each task's start relative to [now]. Oldest first inside a group; empty
/// groups are dropped. Pure.
List<AttentionGroup> groupAttention(List<InboxItem> items, DateTime now) {
  final today = _dayNumber(now);
  final buckets = {
    for (final kind in AttentionGroupKind.values) kind: <InboxItem>[],
  };
  for (final item in items) {
    if (!item.isOverdue) {
      buckets[AttentionGroupKind.dueToday]!.add(item);
      continue;
    }
    final start = item.task.startTime;
    final kind = start == null
        ? AttentionGroupKind.earlier
        : switch (today - _dayNumber(start)) {
            <= 0 => AttentionGroupKind.today,
            1 => AttentionGroupKind.yesterday,
            _ => AttentionGroupKind.earlier,
          };
    buckets[kind]!.add(item);
  }
  return [
    for (final kind in AttentionGroupKind.values)
      if (buckets[kind]!.isNotEmpty)
        AttentionGroup(kind, _oldestFirst(buckets[kind]!)),
  ];
}

/// The overdue items of [groups] (everything except "Due today"), oldest start
/// first overall, whatever order the groups are displayed in. This is the order
/// "Move all to today" places tasks in. Pure.
List<InboxItem> overdueOldestFirst(List<AttentionGroup> groups) =>
    _oldestFirst([
      for (final group in groups)
        if (group.kind != AttentionGroupKind.dueToday) ...group.items,
    ]);

/// Stable: items with equal (or no) start keep their provider order.
List<InboxItem> _oldestFirst(List<InboxItem> items) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final left = a.$2.task.startTime;
    final right = b.$2.task.startTime;
    if (left != null && right != null) {
      final byStart = left.compareTo(right);
      if (byStart != 0) return byStart;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// A planner-local calendar day as a number of days, so two instants on the
/// same planner day compare equal whatever their time of day.
int _dayNumber(DateTime instant) {
  final local = PlannerTimeZone.toPlannerLocal(instant);
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime.utc(1970)).inDays;
}
