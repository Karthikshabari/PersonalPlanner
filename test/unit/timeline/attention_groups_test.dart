import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/inbox_item.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/attention/attention_groups.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');

  DateTime ist(int month, int day, [int hour = 0, int minute = 0]) =>
      PlannerTimeZone.calendarDate(
        2026,
        month,
        day,
        hour: hour,
        minute: minute,
      );

  final now = ist(10, 14, 15);

  InboxItem overdue(String id, DateTime? start) => InboxItem.overdue(
    Task(
      id: id,
      title: id,
      startTime: start,
      endTime: start?.add(const Duration(hours: 1)),
      createdAt: now,
      updatedAt: now,
    ),
  );

  InboxItem capture(String id) => InboxItem.explicit(
    Task(
      id: id,
      title: 'Inbox capture',
      description: id,
      isInbox: true,
      dueDate: '2026-10-14',
      createdAt: now,
      updatedAt: now,
    ),
  );

  List<String> ids(AttentionGroup group) => [
    for (final item in group.items) item.task.id,
  ];

  test('groups are Due today, Earlier, Yesterday, Today, oldest first', () {
    final groups = groupAttention([
      capture('c1'),
      overdue('earlier-old', ist(9, 1, 9)),
      overdue('earlier-new', ist(10, 5, 9)),
      overdue('yesterday', ist(10, 13, 9)),
      overdue('today', ist(10, 14, 8)),
    ], now);
    expect(
      [for (final g in groups) g.kind],
      [
        AttentionGroupKind.dueToday,
        AttentionGroupKind.earlier,
        AttentionGroupKind.yesterday,
        AttentionGroupKind.today,
      ],
    );
    expect(
      [for (final g in groups) g.label],
      ['Due today', 'Earlier', 'Yesterday', 'Today'],
    );
    expect(ids(groups[0]), ['c1']);
    expect(ids(groups[1]), ['earlier-old', 'earlier-new']);
    expect(ids(groups[2]), ['yesterday']);
    expect(ids(groups[3]), ['today']);
  });

  test('empty groups are dropped', () {
    expect(groupAttention(const [], now), isEmpty);
    final groups = groupAttention([overdue('y', ist(10, 13, 9))], now);
    expect(groups, hasLength(1));
    expect(groups.single.kind, AttentionGroupKind.yesterday);
  });

  test('the boundaries are planner midnights', () {
    final groups = groupAttention([
      overdue('a', ist(10, 12, 23, 59)),
      overdue('b', ist(10, 13)),
      overdue('c', ist(10, 13, 23, 59)),
      overdue('d', ist(10, 14)),
    ], now);
    expect(
      [for (final g in groups) g.kind],
      [
        AttentionGroupKind.earlier,
        AttentionGroupKind.yesterday,
        AttentionGroupKind.today,
      ],
    );
    expect(ids(groups[0]), ['a']);
    expect(ids(groups[1]), ['b', 'c']);
    expect(ids(groups[2]), ['d']);
  });

  test('the planner zone decides the day, not UTC', () {
    // 19:00 UTC on Oct 13 is 00:30 on Oct 14 in the planner zone.
    final groups = groupAttention([
      overdue('x', DateTime.utc(2026, 10, 13, 19)),
    ], now);
    expect(groups.single.kind, AttentionGroupKind.today);
  });

  test('items are re-sorted oldest first; ties and no start keep order', () {
    final groups = groupAttention([
      overdue('late', ist(10, 14, 12)),
      overdue('early', ist(10, 14, 8)),
      overdue('none-1', null),
      overdue('none-2', null),
      overdue('same-1', ist(10, 14, 10)),
      overdue('same-2', ist(10, 14, 10)),
    ], now);
    expect(ids(groups.firstWhere((g) => g.kind == AttentionGroupKind.today)), [
      'early',
      'same-1',
      'same-2',
      'late',
    ]);
    // A task with no start is "Earlier" and keeps its place.
    expect(
      ids(groups.firstWhere((g) => g.kind == AttentionGroupKind.earlier)),
      ['none-1', 'none-2'],
    );
  });

  test('explicit captures stay in the given order in Due today', () {
    final groups = groupAttention([capture('c2'), capture('c1')], now);
    expect(groups.single.kind, AttentionGroupKind.dueToday);
    expect(ids(groups.single), ['c2', 'c1']);
  });
}
