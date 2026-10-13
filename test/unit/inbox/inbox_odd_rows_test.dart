import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/inbox/domain/inbox_history.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

/// Plan 4.1: the pairing rules (history only on an Inbox idea, inbox_item_id
/// only on a session) are write-time rules. A row that arrives by sync or
/// backup, or that an older build left behind, is checked for shape only, and
/// must stay editable and portable.
void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late InboxHarness h;

  final closure = InboxClosure(
    kind: InboxCloseKind.closed,
    at: DateTime.utc(2026, 10, 12, 9, 30),
    reason: 'Bought it elsewhere',
    reopenedAt: DateTime.utc(2026, 10, 13, 9, 30),
  );
  final otherClosure = InboxClosure(
    kind: InboxCloseKind.letGo,
    at: DateTime.utc(2026, 10, 14, 9, 30),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    h = InboxHarness(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Stores [history] on [id] the way remote apply does: a raw write with the
  /// outbound triggers suppressed, bypassing the repository's write rules.
  Future<void> storeRaw(
    String id, {
    List<InboxClosure>? history,
    String? inboxItemId,
  }) async {
    await db.syncDao.runWithoutOutbound(() async {
      if (history != null) {
        await db.customStatement(
          'UPDATE tasks SET inbox_history_json = ? WHERE id = ?',
          [InboxHistory.encodeJson(history), id],
        );
      }
      if (inboxItemId != null) {
        await db.customStatement(
          'UPDATE tasks SET inbox_item_id = ? WHERE id = ?',
          [inboxItemId, id],
        );
      }
    });
  }

  /// A plain Day block whose stored history is non-empty: an Inbox session
  /// that an old build converted in place (`is_inbox = 0`).
  Future<Task> convertedBlock() async {
    final idea = await h.idea('Old build converts me');
    final block = await h.session(idea.id, start: h.at(1, 9));
    await storeRaw(block.id, history: [closure]);
    return block;
  }

  group('M1: a non-Inbox row that holds history', () {
    test('(a) an unrelated update succeeds and keeps the history', () async {
      final block = await convertedBlock();
      final stored = await h.reload(block.id);
      expect(stored.isInbox, isFalse);
      expect(stored.inboxHistory, [closure]);

      final updated = await h.tasks.updateTask(
        stored.copyWith(status: TaskStatus.completed),
      );
      expect(updated.status, TaskStatus.completed);
      expect(updated.inboxHistory, [closure]);
      expect((await h.reload(block.id)).inboxHistory, [closure]);

      final moved = await h.tasks.updateTask(
        (await h.reload(block.id)).copyWith(title: 'Renamed'),
      );
      expect(moved.inboxHistory, [closure]);
    });

    test(
      '(a, mirror) an idea with an odd inbox_item_id stays editable',
      () async {
        final other = await h.idea('Another idea');
        final idea = await h.idea('Idea an old build touched');
        await storeRaw(idea.id, inboxItemId: other.id);
        final stored = await h.reload(idea.id);
        expect(stored.isInbox, isTrue);
        expect(stored.inboxItemId, other.id);

        final updated = await h.tasks.updateTask(
          stored.copyWith(title: 'Idea an old build touched, renamed'),
        );
        expect(updated.title, 'Idea an old build touched, renamed');
        expect(updated.inboxItemId, other.id);
        expect((await h.reload(idea.id)).inboxItemId, other.id);
      },
    );

    test('(b) a backup export imports into a fresh database', () async {
      final block = await convertedBlock();
      final source = await BackupService(db).exportJson();

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      final result = await BackupService(restored)
          .importJson(source, ownershipConfirmed: true);
      expect(result.conflicts, isEmpty);

      final row = await restored.taskDao.getTaskById(block.id);
      expect(row, isNotNull);
      expect(row!.isInbox, isFalse);
      expect(InboxHistory.decodeJson(row.inboxHistoryJson), [closure]);
    });

    test(
      '(c) a new write that sets history on a non-Inbox row is refused',
      () async {
        await expectLater(
          h.tasks.insertTask(
            Task(
              id: '',
              title: 'Day block',
              startTime: h.at(1, 9),
              endTime: h.at(1, 10),
              inboxHistory: [closure],
              createdAt: h.now,
              updatedAt: h.now,
            ),
          ),
          throwsArgumentError,
        );

        final idea = await h.idea('An idea');
        final plain = await h.session(idea.id, start: h.at(1, 9));
        await expectLater(
          h.tasks.updateTask(plain.copyWith(inboxHistory: [closure])),
          throwsArgumentError,
        );
        expect((await h.reload(plain.id)).inboxHistory, isEmpty);
      },
    );

    test('(c) an update that changes the odd history is refused', () async {
      final block = await convertedBlock();
      final stored = await h.reload(block.id);
      await expectLater(
        h.tasks.updateTask(stored.copyWith(inboxHistory: [otherClosure])),
        throwsArgumentError,
      );
      await expectLater(
        h.tasks.updateTask(stored.copyWith(inboxHistory: [closure, closure])),
        throwsArgumentError,
      );
      expect((await h.reload(block.id)).inboxHistory, [closure]);
    });

    test('(c) a new link on an Inbox idea is still refused', () async {
      final other = await h.idea('Another idea');
      final idea = await h.idea('An idea');
      await expectLater(
        h.tasks.updateTask(idea.copyWith(inboxItemId: other.id)),
        throwsArgumentError,
      );
      expect((await h.reload(idea.id)).inboxItemId, isNull);
    });

    test('(d) the Inbox board ignores that history', () async {
      final block = await convertedBlock();
      final withOdd = buildInboxBoard(
        await h.inbox.readSource(),
        now: h.now,
        breakDates: const {},
      );
      expect(withOdd.byId.containsKey(block.id), isFalse);
      expect(withOdd.done, isNot(contains(block.id)));
      expect(withOdd.ideas, isNot(contains(block.id)));

      // The same database without that history gives the same board.
      await storeRaw(block.id, history: const []);
      final without = buildInboxBoard(
        await h.inbox.readSource(),
        now: h.now,
        breakDates: const {},
      );
      expect(withOdd, without);
    });
  });
}
