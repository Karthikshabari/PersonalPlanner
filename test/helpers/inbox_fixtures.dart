import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/inbox/domain/inbox_dates.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

/// A fixed planner clock and small builders for Inbox tests.
///
/// [now] is Monday 2026-10-12 12:00 in the planner zone, so "today" is the
/// 12th and the 14-day window ends on Sunday the 25th.
class InboxHarness {
  InboxHarness(this.db)
    : inbox = InboxRepository(db),
      tasks = TaskRepository(db);

  final AppDatabase db;
  final InboxRepository inbox;
  final TaskRepository tasks;

  final DateTime now = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);

  /// Planner wall-clock time [dayOffset] days after today.
  DateTime at(int dayOffset, int hour, [int minute = 0]) =>
      PlannerTimeZone.calendarDate(
        2026,
        10,
        12 + dayOffset,
        hour: hour,
        minute: minute,
      );

  InboxSlot slot(int dayOffset, int hour, {int minutes = 60, int minute = 0}) =>
      InboxSlot(start: at(dayOffset, hour, minute), lengthMin: minutes);

  Future<Task> idea(String text, {String? dueDate}) =>
      inbox.addToInbox(text, dueDate: dueDate);

  /// A session row exactly as Day would hold it (inserted through
  /// TaskRepository, so validation and triggers run).
  Future<Task> session(
    String ideaId, {
    required DateTime start,
    int minutes = 60,
    TaskStatus status = TaskStatus.planned,
    DateTime? createdAt,
    String title = 'Session',
    String? id,
  }) async {
    final created = await tasks.insertTask(
      Task(
        id: id ?? '',
        title: title,
        startTime: start,
        endTime: start.add(Duration(minutes: minutes)),
        inboxItemId: ideaId,
        createdAt: createdAt ?? now.subtract(const Duration(days: 3)),
        updatedAt: now,
      ),
    );
    if (status == TaskStatus.planned) return created;
    return tasks.updateTask(
      created.copyWith(status: status),
      allowStatusTransition: true,
      allowRescheduledTransition: status == TaskStatus.rescheduled,
    );
  }

  Future<List<Task>> sessionsOf(String ideaId) async {
    final rows = await (db.select(
      db.tasks,
    )..where((t) => t.inboxItemId.equals(ideaId))).get();
    return [for (final row in rows) TaskRepository.fromRow(row)];
  }

  Future<Task> reload(String id) async => (await tasks.getTaskById(id))!;

  Future<int> revisionOf(String id) async =>
      (await tasks.getTaskWithRevision(id))!.$2;

  Future<int> syncLogCount() async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM sync_log')
        .getSingle();
    return row.read<int>('c');
  }

  /// Saves a Review reason the way Review does (a daily_reviews row keyed by
  /// the planner date), without going through the Review screen.
  Future<void> saveReviewReason(
    String date,
    Map<String, String> reasons,
  ) async {
    final nowIso = now.toUtc().toIso8601String();
    final entries = reasons.entries
        .map((e) => '"${e.key}":"${e.value}"')
        .join(',');
    await db.customStatement(
      'INSERT OR REPLACE INTO daily_reviews (id, date, task_reasons_json, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['review-$date', date, '{$entries}', nowIso, nowIso],
    );
  }
}

/// Matches the same instant whatever the DateTime subclass or zone flag.
Matcher sameInstant(DateTime expected) => predicate<DateTime>(
  (actual) => actual.isAtSameMomentAs(expected),
  'the instant ${expected.toUtc().toIso8601String()}',
);
