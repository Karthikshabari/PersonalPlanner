import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_aggregate_command.dart';
import 'package:personal_planner/features/task_editor/domain/plan_title_history.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test(
    'undo removes newly added relations without overwriting later edits',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 1, 9);
      try {
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-aggregate',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Daily task',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-09-01',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'aggregate-task',
                title: 'Original title',
                recurringRuleId: const Value('rule-aggregate'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: 'aggregate-tag',
                name: 'new',
                createdAt: now,
                updatedAt: now,
              ),
            );

        final command = RecurrenceAggregateCommand(
          database: db,
          ruleId: 'rule-aggregate',
          description: 'Add tag to series',
          mutation: () async {
            await db
                .into(db.taskTags)
                .insert(
                  TaskTagsCompanion.insert(
                    taskId: 'aggregate-task',
                    tagId: 'aggregate-tag',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          },
        );
        await command.execute();

        await (db.update(db.tasks)
              ..where((task) => task.id.equals('aggregate-task')))
            .write(const TasksCompanion(title: Value('Later edit')));
        await command.undo();

        final link = await (db.select(
          db.taskTags,
        )..where((row) => row.taskId.equals('aggregate-task'))).getSingle();
        expect(link.deletedAt, isNotNull);
        expect(
          (await db.taskDao.getTaskById('aggregate-task'))!.title,
          'Later edit',
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'undo observes a materialized occurrence created after execute',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 1, 9);
      try {
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-late-occurrence',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Daily task',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-09-01',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'aggregate-anchor',
                title: 'Original',
                recurringRuleId: const Value('rule-late-occurrence'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final command = RecurrenceAggregateCommand(
          database: db,
          ruleId: 'rule-late-occurrence',
          description: 'Rename series',
          mutation: () async {
            await (db.update(
              db.recurringRules,
            )..where((rule) => rule.id.equals('rule-late-occurrence'))).write(
              const RecurringRulesCompanion(taskTitle: Value('Renamed')),
            );
          },
        );
        await command.execute();
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'late-materialized',
                title: 'Renamed',
                recurringRuleId: const Value('rule-late-occurrence'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        await command.undo();
        final late = await db.taskDao.getTaskById('late-materialized');
        expect(late?.deletedAt, isNotNull);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'undo restores neighboring tasks shifted during a recurring save',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 1, 9);
      try {
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-with-neighbor',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Daily task',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-09-01',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'rule-anchor',
                title: 'Anchor',
                recurringRuleId: const Value('rule-with-neighbor'),
                startTime: Value(now),
                endTime: Value(now.add(const Duration(minutes: 30))),
                createdAt: now,
                updatedAt: now,
              ),
            );
        final neighborStart = now.add(const Duration(minutes: 15));
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'neighbor',
                title: 'Neighbor',
                startTime: Value(neighborStart),
                endTime: Value(neighborStart.add(const Duration(minutes: 30))),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final command = RecurrenceAggregateCommand(
          database: db,
          ruleId: 'rule-with-neighbor',
          extraTaskIds: const {'neighbor'},
          description: 'Shift neighboring task',
          mutation: () async {
            await (db.update(
              db.tasks,
            )..where((task) => task.id.equals('neighbor'))).write(
              TasksCompanion(
                startTime: Value(neighborStart.add(const Duration(hours: 1))),
                endTime: Value(
                  neighborStart.add(const Duration(hours: 1, minutes: 30)),
                ),
              ),
            );
          },
        );
        await command.execute();
        await command.undo();

        final restored = await db.taskDao.getTaskById('neighbor');
        expect(
          restored?.startTime?.toUtc().millisecondsSinceEpoch,
          neighborStart.toUtc().millisecondsSinceEpoch,
        );
        expect(
          restored?.endTime?.toUtc().millisecondsSinceEpoch,
          neighborStart
              .add(const Duration(minutes: 30))
              .toUtc()
              .millisecondsSinceEpoch,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'undo reverts and redo restores the same recurring plan-change ID',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 1, 9);
      final event = PlanTitleChange(
        id: '00000000-0000-7000-8000-0000000000cc',
        previousTitle: 'Read book',
        newTitle: 'Office work',
        changedAt: now,
      );
      try {
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-plan-undo',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Read book',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-09-01',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'plan-undo-task',
                title: 'Read book',
                recurringRuleId: const Value('rule-plan-undo'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        final command = RecurrenceAggregateCommand(
          database: db,
          ruleId: 'rule-plan-undo',
          description: 'Preserve plan title change',
          mutation: () async {
            await (db.update(
              db.tasks,
            )..where((row) => row.id.equals('plan-undo-task'))).write(
              TasksCompanion(
                title: const Value('Office work'),
                planTitleHistoryJson: Value(
                  PlanTitleHistory.encodeJson([event]),
                ),
                displayPlanChangeId: Value(event.id),
              ),
            );
          },
        );

        await command.execute();
        await command.undo();
        final undone = (await db.taskDao.getTaskById('plan-undo-task'))!;
        final undoneHistory = PlanTitleHistory.decodeJson(
          undone.planTitleHistoryJson,
        );
        expect(undone.title, 'Read book');
        expect(undone.displayPlanChangeId, isNull);
        expect(undoneHistory, hasLength(1));
        expect(undoneHistory.single.id, event.id);
        expect(undoneHistory.single.revertedAt, isNotNull);

        await command.execute();
        final redone = (await db.taskDao.getTaskById('plan-undo-task'))!;
        final redoneHistory = PlanTitleHistory.decodeJson(
          redone.planTitleHistoryJson,
        );
        expect(redone.title, 'Office work');
        expect(redone.displayPlanChangeId, event.id);
        expect(redoneHistory, hasLength(1));
        expect(redoneHistory.single.id, event.id);
        expect(redoneHistory.single.revertedAt, isNull);
      } finally {
        await db.close();
      }
    },
  );
}
