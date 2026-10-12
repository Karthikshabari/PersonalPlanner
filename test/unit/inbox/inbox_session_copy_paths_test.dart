// Every place that builds a task from an existing one, and what it does with
// `inbox_item_id`. A session is linked to its idea only while it is the same
// Day row or the successor of a reschedule; every copy is a plain Day task.
//
//   path                         inbox_item_id   why
//   DuplicateTaskCommand         cleared         a copy is a new plain task
//   Recurrence instances         never set       built from the rule, not a task
//   Task templates               n/a             store no link; apply edits the open task
//   MoveTaskCommand (any day)    kept            the same row moves
//   Edit / status / resize       kept            the same row changes
//   Delete + Undo (snapshot)     kept            the same row comes back
//   Reschedule successor         kept (idea live) that is how a carried session stays linked
//   Reschedule, idea gone        cleared         a link to a missing idea is refused
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task_template.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/inbox/domain/inbox_commands.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/templates/data/template_repository.dart';
import 'package:personal_planner/features/timeline/domain/commands/delete_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/duplicate_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/move_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/resize_task_command.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late InboxHarness h;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    h = InboxHarness(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DuplicateTaskCommand', () {
    test('a duplicated session is a plain Day task', () async {
      final idea = await h.idea('Buy a lamp');
      final source = await h.session(idea.id, start: h.at(1, 9));
      final command = DuplicateTaskCommand(
        repository: h.tasks,
        source: source,
        newStart: h.at(1, 11),
        newEnd: h.at(1, 12),
      );
      await command.execute();

      final all = await db.select(db.tasks).get();
      final copy = all.singleWhere(
        (row) => row.id != source.id && row.id != idea.id,
      );
      expect(copy.inboxItemId, isNull);
      expect(copy.isInbox, isFalse);
      expect(copy.title, source.title);
      // The original keeps its link, and the idea still has one session.
      expect((await h.reload(source.id)).inboxItemId, idea.id);
      expect(await h.sessionsOf(idea.id), hasLength(1));
      expect((await h.inbox.readSource()).sessions, hasLength(1));
    });

    test('duplicating a session whose idea was deleted works', () async {
      final idea = await h.idea('Deleted later');
      final source = await h.session(idea.id, start: h.at(1, 9));
      await h.tasks.deleteTask(idea.id);

      final command = DuplicateTaskCommand(
        repository: h.tasks,
        source: source,
        newStart: h.at(1, 11),
        newEnd: h.at(1, 12),
      );
      await command.execute();
      final copies = (await db.select(db.tasks).get()).where(
        (row) => row.id != source.id && row.id != idea.id,
      );
      expect(copies, hasLength(1));
      expect(copies.single.inboxItemId, isNull);
    });

    test('undo and redo of the duplicate keep it unlinked', () async {
      final idea = await h.idea('Undo me');
      final source = await h.session(idea.id, start: h.at(1, 9));
      final command = DuplicateTaskCommand(
        repository: h.tasks,
        source: source,
        newStart: h.at(1, 11),
        newEnd: h.at(1, 12),
      );
      await command.execute();
      await command.undo();
      await command.execute();
      final live = (await db.select(db.tasks).get()).where(
        (row) =>
            row.id != idea.id && row.id != source.id && row.deletedAt == null,
      );
      expect(live.single.inboxItemId, isNull);
    });
  });

  group('recurrence', () {
    test('instances built from a rule never carry a link', () async {
      final idea = await h.idea('Weekly errand');
      final session = await h.session(idea.id, start: h.at(1, 9));
      // The rule is built from the session's own fields, as the editor does.
      final rules = RecurringRepository(db);
      final rule = await rules.createRule(
        RecurringRule(
          id: 'rule-from-session',
          rrule: 'FREQ=DAILY',
          taskTitle: session.title,
          durationMin: 60,
          startTimeOfDay: '09:00',
          startDate: h.at(2, 0),
          createdAt: h.now,
          updatedAt: h.now,
        ),
      );
      final created = await RecurrenceService(db)
          .materializeForDate(h.at(2, 0));
      expect(created, 1);
      final instance = (await db.select(db.tasks).get()).singleWhere(
        (row) => row.recurringRuleId == rule.id,
      );
      expect(instance.inboxItemId, isNull);
      expect(await h.sessionsOf(idea.id), hasLength(1));
    });

    test(
      'the session that becomes a rule\'s first block stays the same row',
      () async {
        final idea = await h.idea('Becomes recurring');
        final session = await h.session(idea.id, start: h.at(1, 9));
        final rule = await RecurringRepository(db).createRule(
          RecurringRule(
            id: 'rule-for-session',
            rrule: 'FREQ=DAILY',
            taskTitle: session.title,
            durationMin: 60,
            startTimeOfDay: '09:00',
            startDate: h.at(1, 0),
            createdAt: h.now,
            updatedAt: h.now,
          ),
        );
        await h.tasks.updateTask(session.copyWith(recurringRuleId: rule.id));
        expect((await h.reload(session.id)).inboxItemId, idea.id);
      },
    );
  });

  group('templates', () {
    test(
      'a template stores no link (and applying one edits the open task)',
      () async {
        final columns = db.taskTemplates.$columns.map((c) => c.name);
        expect(columns, isNot(contains('inbox_item_id')));
        expect(columns, isNot(contains('inbox_history_json')));

        // Saving a template from a session keeps nothing of the idea.
        final idea = await h.idea('Template source');
        final session = await h.session(idea.id, start: h.at(1, 9));
        final template = await TemplateRepository(db).insertTemplate(
          TaskTemplate(
            id: '',
            name: session.title,
            durationMin: 60,
            createdAt: h.now,
            updatedAt: h.now,
          ),
        );
        expect(template.name, session.title);
        // Applying fills the editor of the open task; the row stays linked.
        await h.tasks.updateTask(session.copyWith(title: template.name));
        expect((await h.reload(session.id)).inboxItemId, idea.id);
      },
    );
  });

  group('moving, editing, resizing, deleting: the same row', () {
    test('moving a session to another day keeps the link, undo too', () async {
      final idea = await h.idea('Move me');
      final session = await h.session(idea.id, start: h.at(1, 9));
      final command = MoveTaskCommand(
        repository: h.tasks,
        original: session,
        newStart: h.at(5, 15),
        newEnd: h.at(5, 16),
      );
      await command.execute();
      var moved = await h.reload(session.id);
      expect(moved.id, session.id);
      expect(moved.inboxItemId, idea.id);
      expect(moved.startTime, sameInstant(h.at(5, 15)));
      await command.undo();
      moved = await h.reload(session.id);
      expect(moved.inboxItemId, idea.id);
      expect(moved.startTime, sameInstant(h.at(1, 9)));
    });

    test('resize, edit and a status change keep the link', () async {
      final idea = await h.idea('Edit me');
      final session = await h.session(idea.id, start: h.at(1, 9));
      await ResizeTaskCommand(
        repository: h.tasks,
        original: session,
        newEnd: h.at(1, 11),
      ).execute();
      var current = await h.reload(session.id);
      await h.tasks.updateTask(current.copyWith(title: 'Edited in Day'));
      current = await h.reload(session.id);
      await h.tasks.updateTask(current.copyWith(status: TaskStatus.completed));
      current = await h.reload(session.id);
      expect(current.inboxItemId, idea.id);
      expect(current.title, 'Edited in Day');
      expect(current.status, TaskStatus.completed);
    });

    test('delete and undo bring the same linked row back, even if the idea is gone', () async {
      final idea = await h.idea('Delete me');
      final session = await h.session(idea.id, start: h.at(1, 9));
      final command = DeleteTaskCommand(repository: h.tasks, original: session);
      await command.execute();
      await h.tasks.deleteTask(idea.id);
      await command.undo();
      final restored = await h.reload(session.id);
      expect(restored.deletedAt, isNull);
      expect(restored.inboxItemId, idea.id);
    });
  });

  group('reschedule successor (a carried session)', () {
    test(
      'RescheduleOverdueCommand keeps the link, undo and redo too',
      () async {
        final idea = await h.idea('Carry me');
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        final command = RescheduleOverdueCommand(
          repository: h.inbox,
          originalId: missed.id,
          start: h.at(2, 9),
          end: h.at(2, 10),
        );
        await command.execute();
        var successor = await h.reload(command.successorId);
        expect(successor.inboxItemId, idea.id);
        expect(successor.rescheduledFromId, missed.id);
        expect((await h.reload(missed.id)).status, TaskStatus.rescheduled);

        await command.undo();
        expect((await h.reload(command.successorId)).deletedAt, isNotNull);
        expect((await h.reload(missed.id)).status, TaskStatus.planned);

        await command.execute();
        successor = await h.reload(command.successorId);
        expect(successor.deletedAt, isNull);
        expect(successor.inboxItemId, idea.id);
      },
    );

    test(
      'the successor of a session whose idea is gone is a plain Day task',
      () async {
        final idea = await h.idea('Gone');
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        await h.tasks.deleteTask(idea.id);
        final command = RescheduleOverdueCommand(
          repository: h.inbox,
          originalId: missed.id,
          start: h.at(2, 9),
          end: h.at(2, 10),
        );
        await command.execute();
        expect((await h.reload(command.successorId)).inboxItemId, isNull);
      },
    );

    test(
      'Save dates carrying a missed session links through rescheduled_to_id',
      () async {
        final idea = await h.idea('Carry via Save');
        final missed = await h.session(idea.id, start: h.at(-1, 9));
        await h.inbox.saveDates(idea.id, [h.slot(1, 9)], h.now);
        final target = (await h.sessionsOf(idea.id))
            .singleWhere((t) => t.id != missed.id);
        expect(target.inboxItemId, idea.id);
        expect((await h.reload(missed.id)).rescheduledToId, target.id);
      },
    );
  });

  test(
    'a drag-created session id is a UUIDv7 and unique per command',
    () async {
      final idea = await h.idea('Two drags');
      final a = ScheduleInboxItemCommand(
        repository: h.inbox,
        itemId: idea.id,
        start: h.at(1, 9),
        end: h.at(1, 10),
      );
      final b = ScheduleInboxItemCommand(
        repository: h.inbox,
        itemId: idea.id,
        start: h.at(2, 9),
        end: h.at(2, 10),
      );
      expect(a.sessionId, isNot(b.sessionId));
      expect(a.sessionId[14], '7');
      expect(generateUuidV7().length, a.sessionId.length);
    },
  );
}
