import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_aggregate_command.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/task_editor/domain/plan_title_history.dart';
import 'package:personal_planner/features/timer/domain/task_actual_duration_service.dart';
import 'package:personal_planner/features/timeline/presentation/providers/undo_stack_provider.dart';

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
    'undo semantically restores an occurrence materialized after execute',
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
        final lateId = generateDeterministicUuid(
          'recurring-occurrence:rule-late-occurrence:2026-09-02',
        );
        final lateStart = PlannerTimeZone.calendarDate(
          2026,
          9,
          2,
          hour: 9,
        );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: lateId,
                title: 'Renamed',
                startTime: Value(lateStart),
                endTime: Value(lateStart.add(const Duration(minutes: 30))),
                recurringRuleId: const Value('rule-late-occurrence'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.syncDao.runWithoutOutbound(() async {
          await db.customStatement(
            'UPDATE tasks SET server_version = 17, sync_status = 0 WHERE id = ?',
            [lateId],
          );
        });

        await command.undo();
        final late = await db.taskDao.getTaskById(lateId);
        expect(late?.deletedAt, isNull);
        expect(late?.title, 'Daily task');
        expect(late?.serverVersion, 17);
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

  test('metadata acknowledgement does not block complete aggregate Undo', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 14, 9);
    try {
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: 'rule-ack',
              rrule: 'FREQ=DAILY',
              taskTitle: 'Plan',
              durationMin: 30,
              startTimeOfDay: '09:00',
              startDate: '2026-09-14',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'task-ack',
              title: 'Plan',
              startTime: Value(now),
              endTime: Value(now.add(const Duration(minutes: 30))),
              recurringRuleId: const Value('rule-ack'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.subtasks)
          .insert(
            SubtasksCompanion.insert(
              id: 'subtask-ack',
              taskId: 'task-ack',
              title: 'Before',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-ack',
              name: 'focus',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.taskTags)
          .insert(
            TaskTagsCompanion.insert(
              taskId: 'task-ack',
              tagId: 'tag-ack',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final command = RecurrenceAggregateCommand(
        database: db,
        ruleId: 'rule-ack',
        description: 'Edit acknowledged series',
        mutation: () async {
          await (db.update(
            db.recurringRules,
          )..where((row) => row.id.equals('rule-ack'))).write(
            const RecurringRulesCompanion(
              startTimeOfDay: Value('11:00'),
              durationMin: Value(60),
            ),
          );
          await (db.update(
            db.tasks,
          )..where((row) => row.id.equals('task-ack'))).write(
            TasksCompanion(
              startTime: Value(now.add(const Duration(hours: 2))),
              endTime: Value(now.add(const Duration(hours: 3))),
            ),
          );
          await (db.update(db.subtasks)
                ..where((row) => row.id.equals('subtask-ack')))
              .write(const SubtasksCompanion(title: Value('After')));
          await (db.update(db.taskTags)..where(
                (row) =>
                    row.taskId.equals('task-ack') & row.tagId.equals('tag-ack'),
              ))
              .write(TaskTagsCompanion(deletedAt: Value(now)));
        },
      );
      await command.execute();

      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: 'timer-after-command',
              taskId: 'task-ack',
              startedAt: now,
              endedAt: Value(now.add(const Duration(minutes: 2))),
              durationSec: const Value(120),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await TaskActualDurationService(db).recomputeTask('task-ack');

      await db.syncDao.runWithoutOutbound(() async {
        await db.customStatement(
          'UPDATE recurring_rules SET server_version = 40, sync_status = 0 WHERE id = ?',
          ['rule-ack'],
        );
        await db.customStatement(
          'UPDATE tasks SET server_version = 41, sync_status = 0 WHERE id = ?',
          ['task-ack'],
        );
        await db.customStatement(
          'UPDATE subtasks SET server_version = 42, sync_status = 0 WHERE id = ?',
          ['subtask-ack'],
        );
        await db.customStatement(
          'UPDATE task_tags SET server_version = 43, sync_status = 0 WHERE task_id = ? AND tag_id = ?',
          ['task-ack', 'tag-ack'],
        );
        await db.delete(db.syncLog).go();
      });

      await command.undo();
      final rule = (await db.recurringRuleDao.getRuleById('rule-ack'))!;
      final task = (await db.taskDao.getTaskById('task-ack'))!;
      final subtask = (await db.subtaskDao.getSubtaskById('subtask-ack'))!;
      final link =
          await (db.select(db.taskTags)..where(
                (row) =>
                    row.taskId.equals('task-ack') & row.tagId.equals('tag-ack'),
              ))
              .getSingle();
      expect(rule.startTimeOfDay, '09:00');
      expect(rule.durationMin, 30);
      expect(rule.serverVersion, 40);
      expect(
        task.startTime?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      expect(
        task.endTime?.millisecondsSinceEpoch,
        now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      );
      expect(task.serverVersion, 41);
      expect(task.actualDurationMin, 2);
      expect(
        await db.timerDao.getSessionById('timer-after-command'),
        isNotNull,
      );
      expect(subtask.title, 'Before');
      expect(subtask.serverVersion, 42);
      expect(link.deletedAt, isNull);
      expect(link.serverVersion, 43);
      final outbound = await db.select(db.syncLog).get();
      expect(
        outbound.map((row) => row.entityTableName),
        containsAll(['recurring_rules', 'tasks', 'subtasks', 'task_tags']),
      );
    } finally {
      await db.close();
    }
  });

  test(
    'a genuine later schedule edit rejects Undo atomically and keeps history',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      final now = DateTime.utc(2026, 9, 14, 9);
      try {
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule-conflict',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Plan',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-09-14',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'task-conflict',
                title: 'Plan',
                startTime: Value(now),
                endTime: Value(now.add(const Duration(minutes: 30))),
                recurringRuleId: const Value('rule-conflict'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        final command = RecurrenceAggregateCommand(
          database: db,
          ruleId: 'rule-conflict',
          description: 'Edit series',
          mutation: () async {
            await (db.update(
              db.recurringRules,
            )..where((row) => row.id.equals('rule-conflict'))).write(
              const RecurringRulesCompanion(
                startTimeOfDay: Value('11:00'),
                durationMin: Value(60),
              ),
            );
            await (db.update(
              db.tasks,
            )..where((row) => row.id.equals('task-conflict'))).write(
              TasksCompanion(
                startTime: Value(now.add(const Duration(hours: 2))),
                endTime: Value(now.add(const Duration(hours: 3))),
              ),
            );
          },
        );
        final notifier = container.read(undoStackProvider.notifier);
        await notifier.execute(command);
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals('task-conflict'))).write(
          TasksCompanion(
            startTime: Value(now.add(const Duration(hours: 5))),
            endTime: Value(now.add(const Duration(hours: 6))),
          ),
        );

        await expectLater(notifier.undo(), throwsA(isA<StateError>()));
        final rule = (await db.recurringRuleDao.getRuleById('rule-conflict'))!;
        final task = (await db.taskDao.getTaskById('task-conflict'))!;
        expect(rule.startTimeOfDay, '11:00');
        expect(rule.durationMin, 60);
        expect(
          task.startTime?.millisecondsSinceEpoch,
          now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
        );
        expect(container.read(undoStackProvider).canUndo, isTrue);
        expect(container.read(undoStackProvider).canRedo, isFalse);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test('rule-exclusion provenance restores through Undo and returns on redo', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final monday = DateTime(2026, 9, 14);
    final tuesday = DateTime(2026, 9, 15);
    try {
      final rules = RecurringRepository(db);
      final recurrence = RecurrenceService(db);
      final original = await rules.createRule(
        RecurringRule(
          id: 'rule-provenance-undo',
          rrule: 'FREQ=DAILY',
          taskTitle: 'Plan',
          durationMin: 30,
          startTimeOfDay: '09:00',
          startDate: monday,
          createdAt: monday,
          updatedAt: monday,
        ),
      );
      await recurrence.materializeForDate(tuesday);
      final occurrenceId = generateDeterministicUuid(
        'recurring-occurrence:${original.id}:2026-09-15',
      );
      final command = RecurrenceAggregateCommand(
        database: db,
        ruleId: original.id,
        description: 'Exclude Tuesday',
        mutation: () async {
          final mondayOnly = await rules.updateRule(
            original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
          );
          await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
        },
      );

      await command.execute();
      expect(
        (await db.taskDao.getTaskById(occurrenceId))?.recurrenceRemovalReason,
        'rule_excluded',
      );
      await db.syncDao.runWithoutOutbound(() async {
        await db.customStatement(
          'UPDATE tasks SET server_version = 51, sync_status = 0 WHERE id = ?',
          [occurrenceId],
        );
        await db.customStatement(
          'UPDATE recurring_rules SET server_version = 52, sync_status = 0 WHERE id = ?',
          [original.id],
        );
      });

      await command.undo();
      var restored = (await db.taskDao.getTaskById(occurrenceId))!;
      expect(restored.deletedAt, isNull);
      expect(restored.recurrenceRemovalReason, isNull);
      expect(restored.serverVersion, 51);
      expect(
        (await db.recurringRuleDao.getRuleById(original.id))?.rrule,
        'FREQ=DAILY',
      );

      await command.execute();
      restored = (await db.taskDao.getTaskById(occurrenceId))!;
      expect(restored.deletedAt, isNotNull);
      expect(restored.recurrenceRemovalReason, 'rule_excluded');
      expect(await recurrence.materializeForDate(tuesday), 0);
    } finally {
      await db.close();
    }
  });

  test('aggregate delete Undo and redo preserve acknowledged metadata', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final monday = DateTime(2026, 9, 14);
    try {
      final rules = RecurringRepository(db);
      final recurrence = RecurrenceService(db);
      final rule = await rules.createRule(
        RecurringRule(
          id: 'rule-delete-undo',
          rrule: 'FREQ=DAILY',
          taskTitle: 'Plan',
          durationMin: 30,
          startTimeOfDay: '09:00',
          startDate: monday,
          createdAt: monday,
          updatedAt: monday,
        ),
      );
      await recurrence.materializeForDate(monday);
      final occurrenceId = generateDeterministicUuid(
        'recurring-occurrence:${rule.id}:2026-09-14',
      );
      final command = RecurrenceAggregateCommand(
        database: db,
        ruleId: rule.id,
        description: 'Delete series',
        mutation: () async {
          await rules.deleteRule(rule.id);
          await recurrence.deleteMaterializedFuture(rule.id, monday);
        },
      );

      await command.execute();
      await db.syncDao.runWithoutOutbound(() async {
        await db.customStatement(
          'UPDATE recurring_rules SET server_version = 61, sync_status = 0 WHERE id = ?',
          [rule.id],
        );
        await db.customStatement(
          'UPDATE tasks SET server_version = 62, sync_status = 0 WHERE id = ?',
          [occurrenceId],
        );
      });

      await command.undo();
      final restoredRule = (await db.recurringRuleDao.getRuleById(rule.id))!;
      final restoredTask = (await db.taskDao.getTaskById(occurrenceId))!;
      expect(restoredRule.deletedAt, isNull);
      expect(restoredRule.serverVersion, 61);
      expect(restoredTask.deletedAt, isNull);
      expect(restoredTask.serverVersion, 62);

      await command.execute();
      expect(
        (await db.recurringRuleDao.getRuleById(rule.id))?.deletedAt,
        isNotNull,
      );
      expect((await db.taskDao.getTaskById(occurrenceId))?.deletedAt, isNotNull);
    } finally {
      await db.close();
    }
  });
}
