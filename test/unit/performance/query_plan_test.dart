import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('key planner queries use the documented indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final now = DateTime.utc(2026, 8, 24, 8);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'category-1',
              name: 'Work',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (var i = 0; i < 100; i++) {
        final start = DateTime.utc(
          2026,
          8,
          23,
          8,
        ).add(Duration(minutes: i * 15));
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'scheduled-$i',
                title: i == 0 ? 'Planning block' : 'Scheduled $i',
                startTime: Value(start),
                endTime: Value(start.add(const Duration(minutes: 30))),
                categoryId: const Value('category-1'),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (var i = 0; i < 900; i++) {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'inbox-$i',
                title: 'Inbox $i',
                isInbox: const Value(true),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: 'rule-1',
              rrule: 'FREQ=DAILY',
              taskTitle: 'Recurring task',
              durationMin: 30,
              startTimeOfDay: '09:00',
              startDate: '2026-08-01',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'recurring-1',
              title: 'Recurring task',
              startTime: Value(DateTime.utc(2026, 8, 24, 9)),
              endTime: Value(DateTime.utc(2026, 8, 24, 9, 30)),
              recurringRuleId: const Value('rule-1'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: 'timer-1',
              taskId: 'scheduled-1',
              startedAt: now,
              state: const Value('running'),
              runningSince: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.customStatement('ANALYZE');

      final queries = <String, String>{
        'day/week': """
          SELECT id FROM tasks
          WHERE deleted_at IS NULL AND is_inbox = 0
            AND start_time < '2026-08-25T00:00:00.000Z'
            AND end_time > '2026-08-24T00:00:00.000Z'
          ORDER BY start_time
        """,
        'inbox/overdue': """
          SELECT id FROM tasks
          WHERE deleted_at IS NULL AND is_inbox = 0
            AND status IN ('planned', 'in_progress')
            AND end_time < '2026-08-24T00:00:00.000Z'
          ORDER BY end_time
        """,
        'inbox': """
          SELECT id FROM tasks
          WHERE deleted_at IS NULL AND is_inbox = 1
          ORDER BY status
        """,
        'fts': """
          SELECT rowid FROM tasks_fts
          WHERE tasks_fts MATCH 'planning'
        """,
        'analytics': """
          SELECT id FROM tasks
          WHERE category_id = 'category-1'
            AND deleted_at IS NULL AND is_inbox = 0
            AND start_time >= '2026-08-24T00:00:00.000Z'
            AND start_time < '2026-08-31T00:00:00.000Z'
          ORDER BY start_time
        """,
        'timer': """
          SELECT id FROM timer_sessions
          WHERE task_id = 'task-1' AND deleted_at IS NULL
          ORDER BY started_at
        """,
        'recurrence': """
          SELECT id FROM tasks
          WHERE recurring_rule_id = 'rule-1' AND deleted_at IS NULL
            AND start_time >= '2026-08-24T00:00:00.000Z'
            AND start_time < '2026-08-25T00:00:00.000Z'
          ORDER BY start_time
        """,
        'pending-sync': """
          SELECT operation_id FROM sync_log
          WHERE state IN ('pending', 'error')
            AND (next_attempt_at IS NULL OR next_attempt_at <= '2026-08-24T00:00:00.000Z')
          ORDER BY state, next_attempt_at, created_at
          LIMIT 100
        """,
      };

      final expectedIndexes = <String, String>{
        'day/week': 'idx_tasks_day',
        'inbox/overdue': 'idx_tasks_overdue',
        'inbox': 'idx_tasks_inbox',
        'analytics': 'idx_tasks_category_date',
        'timer': 'idx_timer_sessions_task',
        'recurrence': 'idx_tasks_recurring',
        'pending-sync': 'idx_sync_log_pending',
      };

      for (final entry in queries.entries) {
        final rows = await db
            .customSelect('EXPLAIN QUERY PLAN ${entry.value}')
            .get();
        final plan = rows.map((row) => row.data.values.join(' ')).join('\n');
        // Keep the evidence visible in expanded test output for the release
        // record while asserting the access path remains intentional.
        debugPrint('${entry.key}: $plan');
        if (entry.key == 'fts') {
          expect(plan, contains('VIRTUAL TABLE'));
        } else {
          expect(plan, contains(expectedIndexes[entry.key]!));
        }
      }
    } finally {
      await db.close();
    }
  });
}
