import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:personal_planner/core/models/category.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/enums/recurrence_removal_reason.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/task_template.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/templates/data/template_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late RecurringRepository rules;
  late TemplateRepository templates;
  late TaskRepository tasks;
  late CategoryRepository categories;
  late RecurrenceService recurrence;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    rules = RecurringRepository(db);
    templates = TemplateRepository(db);
    tasks = TaskRepository(db);
    categories = CategoryRepository(db);
    recurrence = RecurrenceService(db);
    await categories.seedDefaultsIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Category> workCategory() async =>
      (await categories.getAllCategories()).first;

  RecurringRule dailyRule({
    String rrule = 'FREQ=DAILY',
    DateTime? startDate,
    String title = 'Standup',
  }) => RecurringRule(
    id: '',
    rrule: rrule,
    taskTitle: title,
    durationMin: 30,
    startTimeOfDay: '09:00',
    startDate: startDate ?? DateTime(2026, 8, 1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('RecurrenceService.materializeForDate', () {
    test('daily rule materializes once per day and never duplicates', () async {
      await rules.createRule(dailyRule());

      final monday = DateTime(2026, 8, 24);
      expect(await recurrence.materializeForDate(monday), 1);
      // Second run for the same day is a no-op.
      expect(await recurrence.materializeForDate(monday), 0);

      final dayTasks = await tasks.watchTasksForDay(monday).first;
      expect(dayTasks, hasLength(1));
      final instance = dayTasks.single;
      expect(instance.title, 'Standup');
      expect(instance.startTime!.hour, 9);
      expect(instance.startTime!.minute, 0);
      expect(
        instance.endTime!.difference(instance.startTime!),
        const Duration(minutes: 30),
      );
      expect(instance.estimatedDurationMin, 30);
      expect(instance.status, TaskStatus.planned);
      expect(instance.isInbox, false);
      expect(
        instance.id,
        generateDeterministicUuid(
          'recurring-occurrence:${(await rules.getActiveRules()).single.id}:2026-08-24',
        ),
      );
    });

    test(
      'moving an occurrence does not recreate its original identity',
      () async {
        final rule = await rules.createRule(dailyRule());
        final originalDate = DateTime(2026, 8, 24);
        expect(await recurrence.materializeForDate(originalDate), 1);
        final occurrence =
            (await tasks.watchTasksForDay(originalDate).first).single;
        final movedStart = DateTime(2026, 8, 26, 9);
        await tasks.updateTask(
          occurrence.copyWith(
            startTime: movedStart,
            endTime: movedStart.add(const Duration(minutes: 30)),
          ),
        );

        expect(await recurrence.materializeForDate(originalDate), 0);
        final all = await db.recurringRuleDao.getInstancesForDay(
          rule.id,
          DateTime(2026, 8, 1).toUtc().toIso8601String(),
          DateTime(2026, 9, 1).toUtc().toIso8601String(),
        );
        expect(all.where((row) => row.id == occurrence.id), hasLength(1));
      },
    );

    test('weekdays rule skips weekend days', () async {
      await rules.createRule(
        dailyRule(rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
      );

      // Aug 22 2026 = Saturday, Aug 23 = Sunday, Aug 24 = Monday.
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 22)), 0);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 23)), 0);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
    });

    test('weekly rule with BYDAY only occurs on the selected days', () async {
      await rules.createRule(dailyRule(rrule: 'FREQ=WEEKLY;BYDAY=WE'));

      // Aug 26 2026 = Wednesday.
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 26)), 1);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 27)), 0);
    });

    test('interval=2 weekly respects the interval', () async {
      await rules.createRule(
        dailyRule(rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'),
      );
      // DTSTART Aug 1 2026 (Sat) anchors the fortnight at the week of
      // Jul 27 → Mondays Aug 10, Aug 24, Sep 7 … (Aug 17 belongs to the
      // skipped week).
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 10)), 1);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 17)), 0);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
    });

    test('monthly BYMONTHDAY occurs on that day of month', () async {
      await rules.createRule(dailyRule(rrule: 'FREQ=MONTHLY;BYMONTHDAY=15'));
      expect(await recurrence.materializeForDate(DateTime(2026, 9, 15)), 1);
      expect(await recurrence.materializeForDate(DateTime(2026, 9, 16)), 0);
    });

    test('exceptions are excluded from materialization', () async {
      final rule = await rules.createRule(dailyRule());
      await rules.addException(rule.id, DateTime(2026, 8, 25));

      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 25)), 0);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 26)), 1);
    });

    test('end_date stops materialization after the last occurrence', () async {
      final rule = await rules.createRule(dailyRule());
      await rules.setEndDate(rule.id, DateTime(2026, 8, 24));

      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 25)), 0);
    });

    test('rules starting in the future do not materialize early', () async {
      await rules.createRule(dailyRule(startDate: DateTime(2026, 9, 1)));
      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 0);
      expect(await recurrence.materializeForDate(DateTime(2026, 9, 1)), 1);
    });

    test('deactivated and soft-deleted rules are skipped', () async {
      final active = await rules.createRule(dailyRule(title: 'Active'));
      final deactivated = await rules.createRule(dailyRule(title: 'Inactive'));
      await rules.deactivateRule(deactivated.id);
      final deleted = await rules.createRule(dailyRule(title: 'Deleted'));
      await rules.deleteRule(deleted.id);

      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
      final dayTasks = await tasks
          .watchTasksForDay(DateTime(2026, 8, 24))
          .first;
      expect(dayTasks.single.title, active.taskTitle);
      expect(dayTasks.single.title, 'Active');
    });

    test('materialized instances carry category, priority and tags', () async {
      final category = await workCategory();
      // Create a tag directly to link from the rule.
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-1',
              name: 'focus',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await rules.createRule(
        dailyRule().copyWith(
          categoryId: category.id,
          priority: 3,
          tags: ['tag-1'],
        ),
      );

      expect(await recurrence.materializeForDate(DateTime(2026, 8, 24)), 1);
      final instance =
          (await tasks.watchTasksForDay(DateTime(2026, 8, 24)).first).single;
      expect(instance.categoryId, category.id);
      expect(instance.priority.dbValue, 3);
      final linkedRows = await (db.select(
        db.taskTags,
      )..where((tt) => tt.taskId.equals(instance.id))).get();
      expect(linkedRows.map((r) => r.tagId), ['tag-1']);
    });
  });

  group('delete-scope helpers', () {
    test('addException is idempotent and setEndDate persists', () async {
      final rule = await rules.createRule(dailyRule());
      await rules.addException(rule.id, DateTime(2026, 8, 24));
      await rules.addException(rule.id, DateTime(2026, 8, 24));

      final stored = await rules.getRuleById(rule.id);
      expect(stored!.exceptions, ['2026-08-24']);

      await rules.setEndDate(rule.id, DateTime(2026, 12, 31));
      expect(
        (await rules.getRuleById(rule.id))!.endDate,
        DateTime(2026, 12, 31),
      );
    });
  });

  test(
    'all-future reconciliation tombstones slots removed by the new rule',
    () async {
      final original = await rules.createRule(
        dailyRule(startDate: DateTime(2026, 8, 1)),
      );
      final monday = DateTime(2026, 8, 24, 9);
      final tuesday = DateTime(2026, 8, 25, 9);
      final mondayTask = await tasks.insertTask(
        Task(
          id: generateDeterministicUuid(
            'recurring-occurrence:${original.id}:2026-08-24',
          ),
          title: 'Old title',
          startTime: monday,
          endTime: monday.add(const Duration(minutes: 30)),
          recurringRuleId: original.id,
          createdAt: monday,
          updatedAt: monday,
        ),
      );
      final tuesdayTask = await tasks.insertTask(
        Task(
          id: generateDeterministicUuid(
            'recurring-occurrence:${original.id}:2026-08-25',
          ),
          title: 'Obsolete title',
          startTime: tuesday,
          endTime: tuesday.add(const Duration(minutes: 30)),
          recurringRuleId: original.id,
          createdAt: tuesday,
          updatedAt: tuesday,
        ),
      );

      final updated = original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO');
      await recurrence.reconcileMaterializedFuture(updated, monday);

      final kept = await tasks.getTaskById(mondayTask.id);
      final removed = await tasks.getTaskById(tuesdayTask.id);
      expect(kept!.deletedAt, isNull);
      expect(kept.title, updated.taskTitle);
      expect(removed!.deletedAt, isNotNull);
      expect(
        removed.recurrenceRemovalReason,
        RecurrenceRemovalReason.ruleExcluded,
      );
    },
  );

  test(
    'daily to Monday-only to daily reactivates one original Tuesday identity',
    () async {
      final monday = DateTime(2026, 9, 14);
      final tuesday = DateTime(2026, 9, 15);
      final original = await rules.createRule(dailyRule(startDate: monday));
      expect(await recurrence.materializeForDate(tuesday), 1);
      final occurrenceId = generateDeterministicUuid(
        'recurring-occurrence:${original.id}:2026-09-15',
      );

      final mondayOnly = await rules.updateRule(
        original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
      );
      await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
      expect(
        (await db.taskDao.getTaskById(occurrenceId))?.deletedAt,
        isNotNull,
      );

      final daily = await rules.updateRule(
        mondayOnly.copyWith(rrule: 'FREQ=DAILY'),
      );
      await recurrence.reconcileMaterializedFuture(daily, monday);
      expect(await recurrence.materializeForDate(tuesday), 1);
      expect(await recurrence.materializeForDate(tuesday), 0);
      expect(await recurrence.materializeForDate(tuesday), 0);

      final all = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(occurrenceId))).get();
      expect(all, hasLength(1));
      expect(all.single.deletedAt, isNull);
      expect(all.single.recurrenceRemovalReason, isNull);
    },
  );

  test('explicit deletion and recurrence exception never reactivate', () async {
    final monday = DateTime(2026, 9, 14);
    final tuesday = DateTime(2026, 9, 15);
    final original = await rules.createRule(dailyRule(startDate: monday));
    await recurrence.materializeForDate(tuesday);
    final occurrence = (await tasks.watchTasksForDay(tuesday).first).single;
    await tasks.deleteTask(occurrence.id);
    await rules.addException(original.id, tuesday);

    final mondayOnly = await rules.updateRule(
      (await rules.getRuleById(original.id))!
          .copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
    );
    await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
    final daily = await rules.updateRule(
      mondayOnly.copyWith(rrule: 'FREQ=DAILY'),
    );
    await recurrence.reconcileMaterializedFuture(daily, monday);

    expect(await recurrence.materializeForDate(tuesday), 0);
    final deleted = await db.taskDao.getTaskById(occurrence.id);
    expect(deleted?.deletedAt, isNotNull);
    expect(deleted?.recurrenceRemovalReason, isNull);
  });

  test('an exception blocks a rule-excluded tombstone from reactivation', () async {
    final monday = DateTime(2026, 9, 14);
    final tuesday = DateTime(2026, 9, 15);
    final original = await rules.createRule(dailyRule(startDate: monday));
    await recurrence.materializeForDate(tuesday);
    final occurrenceId = generateDeterministicUuid(
      'recurring-occurrence:${original.id}:2026-09-15',
    );
    final mondayOnly = await rules.updateRule(
      original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
    );
    await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
    await rules.addException(original.id, tuesday);
    final withException = (await rules.getRuleById(original.id))!;
    await rules.updateRule(withException.copyWith(rrule: 'FREQ=DAILY'));

    expect(await recurrence.materializeForDate(tuesday), 0);
    final row = await db.taskDao.getTaskById(occurrenceId);
    expect(row?.deletedAt, isNotNull);
    expect(row?.recurrenceRemovalReason, 'rule_excluded');
  });

  test(
    'completed skipped and cancelled occurrences are never revived',
    () async {
      final monday = DateTime(2026, 9, 14);
      final original = await rules.createRule(dailyRule(startDate: monday));
      final statuses = [
        TaskStatus.completed,
        TaskStatus.skipped,
        TaskStatus.cancelled,
      ];
      for (var i = 0; i < statuses.length; i++) {
        final day = monday.add(Duration(days: i + 1));
        await recurrence.materializeForDate(day);
        final task = (await tasks.watchTasksForDay(day).first).single;
        await tasks.updateTask(task.copyWith(status: statuses[i]));
      }

      final mondayOnly = await rules.updateRule(
        original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
      );
      await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
      final daily = await rules.updateRule(
        mondayOnly.copyWith(rrule: 'FREQ=DAILY'),
      );
      await recurrence.reconcileMaterializedFuture(daily, monday);

      final rows = await (db.select(
        db.tasks,
      )..where((row) => row.recurringRuleId.equals(original.id))).get();
      expect(
        rows.map((row) => TaskStatus.fromDb(row.status)),
        containsAll(statuses),
      );
      expect(rows.every((row) => row.deletedAt == null), isTrue);
      expect(rows.every((row) => row.recurrenceRemovalReason == null), isTrue);
    },
  );

  test(
    'a moved occurrence is not tombstoned or duplicated at its original slot',
    () async {
      final monday = DateTime(2026, 9, 14);
      final tuesday = DateTime(2026, 9, 15);
      final original = await rules.createRule(dailyRule(startDate: monday));
      await recurrence.materializeForDate(tuesday);
      final occurrence = (await tasks.watchTasksForDay(tuesday).first).single;
      final movedStart = DateTime(2026, 9, 16, 14);
      await tasks.updateTask(
        occurrence.copyWith(
          startTime: movedStart,
          endTime: movedStart.add(const Duration(minutes: 30)),
        ),
      );

      final mondayOnly = await rules.updateRule(
        original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
      );
      await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
      final daily = await rules.updateRule(
        mondayOnly.copyWith(rrule: 'FREQ=DAILY'),
      );
      await recurrence.reconcileMaterializedFuture(daily, monday);
      expect(await recurrence.materializeForDate(tuesday), 0);

      final rows = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(occurrence.id))).get();
      expect(rows, hasLength(1));
      expect(rows.single.deletedAt, isNull);
      expect(
        rows.single.startTime?.millisecondsSinceEpoch,
        movedStart.millisecondsSinceEpoch,
      );
    },
  );

  test('rule-exclusion provenance survives a sync round trip', () async {
    final target = AppDatabase(NativeDatabase.memory());
    try {
      final monday = DateTime(2026, 9, 14);
      final tuesday = DateTime(2026, 9, 15);
      final original = await rules.createRule(dailyRule(startDate: monday));
      await recurrence.materializeForDate(tuesday);
      final occurrenceId = generateDeterministicUuid(
        'recurring-occurrence:${original.id}:2026-09-15',
      );
      final sourceRule = await db.recurringRuleDao.getRuleById(original.id);
      final sourceTask = await db.taskDao.getTaskById(occurrenceId);
      await target
          .into(target.recurringRules)
          .insert(sourceRule!.toCompanion(false));
      await target.into(target.tasks).insert(sourceTask!.toCompanion(false));

      final mondayOnly = await rules.updateRule(
        original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
      );
      await recurrence.reconcileMaterializedFuture(mondayOnly, monday);
      final operation =
          await (db.select(db.syncLog)
                ..where((row) => row.recordId.equals(occurrenceId))
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                ..limit(1))
              .getSingle();
      final payload = Map<String, dynamic>.from(
        jsonDecode(operation.payload) as Map,
      );
      expect(operation.operation, 'update');
      expect(
        payload['recurrence_removal_reason'],
        RecurrenceRemovalReason.ruleExcluded,
      );
      await SyncRemoteApplier(target).apply(
        SyncRemoteChange(
          changeId: 1,
          operationId: operation.operationId,
          tableName: 'tasks',
          recordId: occurrenceId,
          operation: 'update',
          serverVersion: 7,
          serverTimestamp: DateTime.now().toUtc(),
          payload: payload,
        ),
      );
      final received = await target.taskDao.getTaskById(occurrenceId);
      expect(received?.deletedAt, isNotNull);
      expect(
        received?.recurrenceRemovalReason,
        RecurrenceRemovalReason.ruleExcluded,
      );
    } finally {
      await target.close();
    }
  });

  test('reactivation remains stable across two database reopens', () async {
    final directory = Directory.systemTemp.createTempSync(
      'planner_f04_restart',
    );
    final file = File('${directory.path}/planner.sqlite3');
    try {
      var reopened = AppDatabase(NativeDatabase(file));
      final reopenedRules = RecurringRepository(reopened);
      var reopenedService = RecurrenceService(reopened);
      final monday = DateTime(2026, 9, 14);
      final tuesday = DateTime(2026, 9, 15);
      final original = await reopenedRules.createRule(
        dailyRule(startDate: monday),
      );
      await reopenedService.materializeForDate(tuesday);
      final mondayOnly = await reopenedRules.updateRule(
        original.copyWith(rrule: 'FREQ=WEEKLY;BYDAY=MO'),
      );
      await reopenedService.reconcileMaterializedFuture(mondayOnly, monday);
      await reopenedRules.updateRule(mondayOnly.copyWith(rrule: 'FREQ=DAILY'));
      await reopened.close();

      reopened = AppDatabase(NativeDatabase(file));
      reopenedService = RecurrenceService(reopened);
      expect(await reopenedService.materializeForDate(tuesday), 1);
      await reopened.close();

      reopened = AppDatabase(NativeDatabase(file));
      reopenedService = RecurrenceService(reopened);
      expect(await reopenedService.materializeForDate(tuesday), 0);
      final occurrenceId = generateDeterministicUuid(
        'recurring-occurrence:${original.id}:2026-09-15',
      );
      expect(
        (await reopened.taskDao.getTaskById(occurrenceId))?.deletedAt,
        isNull,
      );
      await reopened.close();
    } finally {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  });

  test(
    'all-future title preservation touches only prior unfinished instances',
    () async {
      final original = await rules.createRule(
        dailyRule(startDate: DateTime(2026, 8, 24), title: 'Read book'),
      );
      final monday = DateTime(2026, 8, 24, 9);
      final tuesday = DateTime(2026, 8, 25, 9);
      final wednesday = DateTime(2026, 8, 26, 9);
      final selected = await tasks.insertTask(
        Task(
          id: generateDeterministicUuid(
            'recurring-occurrence:${original.id}:2026-08-24',
          ),
          title: 'Read book',
          startTime: monday,
          endTime: monday.add(const Duration(minutes: 30)),
          recurringRuleId: original.id,
          createdAt: monday,
          updatedAt: monday,
        ),
      );
      final affected = await tasks.insertTask(
        Task(
          id: generateDeterministicUuid(
            'recurring-occurrence:${original.id}:2026-08-25',
          ),
          title: 'Custom prior title',
          startTime: tuesday,
          endTime: tuesday.add(const Duration(minutes: 30)),
          recurringRuleId: original.id,
          createdAt: tuesday,
          updatedAt: tuesday,
        ),
      );
      final completed = await tasks.insertTask(
        Task(
          id: generateDeterministicUuid(
            'recurring-occurrence:${original.id}:2026-08-26',
          ),
          title: 'Completed title',
          startTime: wednesday,
          endTime: wednesday.add(const Duration(minutes: 30)),
          recurringRuleId: original.id,
          status: TaskStatus.completed,
          createdAt: wednesday,
          updatedAt: wednesday,
        ),
      );
      final updated = original.copyWith(taskTitle: 'Office work');
      await rules.updateRule(updated);
      final changedAt = DateTime.utc(2026, 9, 13, 10);
      const intentId = '00000000-0000-7000-8000-0000000000aa';

      await recurrence.reconcileMaterializedFuture(
        updated,
        monday,
        excludeTaskId: selected.id,
        planTitleChangeIntentId: intentId,
        planTitleChangedAt: changedAt,
        preservePlanTitleChange: true,
      );

      final selectedAfter = (await tasks.getTaskById(selected.id))!;
      final affectedAfter = (await tasks.getTaskById(affected.id))!;
      final completedAfter = (await tasks.getTaskById(completed.id))!;
      final expectedEventId = generateDeterministicUuid(
        'plan-title-change:$intentId:${affected.id}',
      );
      expect(selectedAfter.title, 'Read book');
      expect(selectedAfter.planTitleHistory, isEmpty);
      expect(affectedAfter.title, 'Office work');
      expect(affectedAfter.planTitleHistory, hasLength(1));
      expect(affectedAfter.planTitleHistory.single.id, expectedEventId);
      expect(
        affectedAfter.planTitleHistory.single.previousTitle,
        'Custom prior title',
      );
      expect(affectedAfter.displayPlanChangeId, expectedEventId);
      expect(completedAfter.title, 'Completed title');
      expect(completedAfter.planTitleHistory, isEmpty);

      // A new unmaterialized occurrence starts at the rule title and has no
      // fabricated plan-history event.
      await recurrence.materializeForDate(DateTime(2026, 8, 27));
      final fresh =
          (await tasks.watchTasksForDay(DateTime(2026, 8, 27)).first).single;
      expect(fresh.title, 'Office work');
      expect(fresh.planTitleHistory, isEmpty);
      expect(fresh.displayPlanChangeId, isNull);
    },
  );

  group('RecurringRepository CRUD', () {
    test('create/update/deactivate/soft-delete + watchActiveRules', () async {
      final created = await rules.createRule(dailyRule());
      expect(created.id, isNotEmpty);

      await rules.updateRule(created.copyWith(taskTitle: 'Renamed'));
      expect((await rules.getRuleById(created.id))!.taskTitle, 'Renamed');

      final watched = <List<RecurringRule>>[];
      final sub = rules.watchActiveRules().listen(watched.add);
      await pumpEventQueue();

      await rules.deactivateRule(created.id);
      await pumpEventQueue();
      final lastActive = watched.last.where(
        (r) => r.isActive && r.deletedAt == null,
      );
      expect(lastActive, isEmpty);

      await sub.cancel();
    });
  });

  group('TemplateRepository CRUD', () {
    test('insert, watchAllTemplates, update, delete', () async {
      final template = await templates.insertTemplate(
        TaskTemplate(
          id: '',
          name: 'Deep Work',
          description: '90 minutes of focus',
          durationMin: 90,
          priority: 2,
          tags: const ['tag-1'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final all = await templates.getAllTemplates();
      expect(all.single.name, 'Deep Work');
      expect(all.single.tags, ['tag-1']);

      final watched = <List<TaskTemplate>>[];
      final sub = templates.watchAllTemplates().listen(watched.add);
      await pumpEventQueue();

      await templates.updateTemplate(template.copyWith(name: 'Focus Block'));
      await pumpEventQueue();
      expect(watched.last.single.name, 'Focus Block');

      await templates.deleteTemplate(template.id);
      await pumpEventQueue();
      expect(watched.last, isEmpty);

      await sub.cancel();
    });
  });
}
