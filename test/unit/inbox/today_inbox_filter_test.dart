import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/inbox_item.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

void main() {
  setUp(() => PlannerTimeZone.initialize(identifier: 'Asia/Kolkata'));

  InboxItem item(String? dueDate) => InboxItem.explicit(
    Task(
      id: 'capture-${dueDate ?? 'none'}',
      title: 'Inbox capture',
      description: 'Capture',
      isInbox: true,
      inboxContentVersion: 1,
      dueDate: dueDate,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  test('Today keeps undated and only current-week dated Inbox items', () {
    final wednesday = DateTime.utc(2026, 9, 16, 6, 30); // 12:00 IST.
    expect(isInboxItemVisibleInToday(item(null), wednesday), isTrue);
    expect(isInboxItemVisibleInToday(item('2026-09-16'), wednesday), isTrue);
    expect(isInboxItemVisibleInToday(item('2026-09-14'), wednesday), isTrue);
    expect(isInboxItemVisibleInToday(item('2026-09-20'), wednesday), isTrue);
    expect(isInboxItemVisibleInToday(item('2026-09-13'), wednesday), isFalse);
    expect(isInboxItemVisibleInToday(item('2026-09-21'), wednesday), isFalse);
  });

  test('current-week filtering crosses month and year boundaries', () {
    final monthBoundary = DateTime.utc(2026, 9, 30, 6, 30);
    expect(
      isInboxItemVisibleInToday(item('2026-10-04'), monthBoundary),
      isTrue,
    );
    expect(
      isInboxItemVisibleInToday(item('2026-10-05'), monthBoundary),
      isFalse,
    );

    final yearBoundary = DateTime.utc(2026, 12, 31, 6, 30);
    expect(isInboxItemVisibleInToday(item('2027-01-03'), yearBoundary), isTrue);
    expect(
      isInboxItemVisibleInToday(item('2027-01-04'), yearBoundary),
      isFalse,
    );
  });

  test('today is derived from planner-local time at a timezone boundary', () {
    // Sunday 20:00 UTC is Monday 01:30 in Asia/Kolkata, so the new planner
    // week has begun even though the UTC calendar date is still Sunday.
    final boundary = DateTime.utc(2026, 9, 20, 20);
    expect(isInboxItemVisibleInToday(item('2026-09-21'), boundary), isTrue);
    expect(isInboxItemVisibleInToday(item('2026-09-20'), boundary), isFalse);
  });
}
