import 'package:personal_planner/core/models/category.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task_template.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/templates/data/template_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/core/utils/uuid.dart';

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
