import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/settings/data/backup_codec.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  // The session id sorts before its idea's id, so any code that inserts in id
  // order would hit the foreign key before the idea exists.
  const closedIdeaId = '00000000-0000-4000-8000-0000000000b1';
  const openIdeaId = '00000000-0000-4000-8000-0000000000b2';
  const sessionId = '00000000-0000-4000-8000-0000000000a1';
  const secondSessionId = '00000000-0000-4000-8000-0000000000a2';
  final closedAt = DateTime.utc(2026, 10, 12, 9, 30);
  final reopenedAt = DateTime.utc(2026, 10, 13, 9, 30);
  final created = DateTime.utc(2026, 10, 11, 8);

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final repo = TaskRepository(database, clock: () => created);
    await repo.insertTask(
      Task(
        id: closedIdeaId,
        title: 'Buy a lamp',
        description: 'Buy a lamp',
        isInbox: true,
        inboxContentVersion: 1,
        createdAt: created,
        updatedAt: created,
        inboxHistory: [
          InboxClosure(
            kind: InboxCloseKind.closed,
            at: closedAt,
            reason: 'Bought it elsewhere',
            reopenedAt: reopenedAt,
          ),
          InboxClosure(kind: InboxCloseKind.letGo, at: reopenedAt),
        ],
      ),
    );
    await repo.insertTask(
      Task(
        id: openIdeaId,
        title: 'Learn C',
        description: 'Learn C',
        isInbox: true,
        inboxContentVersion: 1,
        createdAt: created,
        updatedAt: created,
      ),
    );
    await repo.insertTask(
      Task(
        id: sessionId,
        title: 'Learn C',
        startTime: DateTime.utc(2026, 10, 14, 9),
        endTime: DateTime.utc(2026, 10, 14, 10),
        inboxItemId: openIdeaId,
        createdAt: created,
        updatedAt: created,
      ),
    );
    await repo.insertTask(
      Task(
        id: secondSessionId,
        title: 'Ordinary block',
        startTime: DateTime.utc(2026, 10, 14, 11),
        endTime: DateTime.utc(2026, 10, 14, 12),
        createdAt: created,
        updatedAt: created,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Map<String, dynamic> dataOf(Map<String, dynamic> document) =>
      (document['content'] as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  /// Re-seals a document after a test changed its data.
  String reseal(Map<String, dynamic> document, {int? version}) {
    final content = document['content'] as Map<String, dynamic>;
    if (version != null) {
      document['schema_version'] = version;
      content['schema_version'] = version;
    }
    (document['validation'] as Map<String, dynamic>)['record_counts'] =
        BackupCodec.recordCounts(content['data'] as Map<String, dynamic>);
    document['content_checksum'] = BackupCodec.checksum(content);
    return jsonEncode(document);
  }

  Future<Map<String, dynamic>> exported() async =>
      jsonDecode(await BackupService(database).exportJson())
          as Map<String, dynamic>;

  Map<String, dynamic> taskRow(Map<String, dynamic> data, String id) =>
      (data['tasks'] as List).cast<Map<String, dynamic>>().firstWhere(
        (row) => row['id'] == id,
      );

  test('the format version is 9', () {
    expect(plannerBackupSchemaVersion, 9);
  });

  test('export carries both keys on every task row', () async {
    final document = await exported();
    expect(document['schema_version'], 9);
    final tasks = (dataOf(document)['tasks'] as List)
        .cast<Map<String, dynamic>>();
    expect(tasks, hasLength(4));
    for (final row in tasks) {
      expect(row.containsKey('inbox_item_id'), isTrue);
      expect(row.containsKey('inbox_history'), isTrue);
    }
    final data = dataOf(document);
    expect(taskRow(data, sessionId)['inbox_item_id'], openIdeaId);
    expect(taskRow(data, sessionId)['inbox_history'], isEmpty);
    expect(taskRow(data, secondSessionId)['inbox_item_id'], isNull);
    expect(taskRow(data, openIdeaId)['inbox_history'], isEmpty);
    final history = taskRow(data, closedIdeaId)['inbox_history'] as List;
    expect(history, hasLength(2));
    expect((history.first as Map)['kind'], 'closed');
    expect((history.first as Map)['reason'], 'Bought it elsewhere');
    expect((history.first as Map)['at'], '2026-10-12T09:30:00.000Z');
    expect((history.first as Map)['reopened_at'], '2026-10-13T09:30:00.000Z');
    expect((history.last as Map)['kind'], 'let_go');
    expect((history.last as Map)['reopened_at'], isNull);
  });

  test('a merge round trip keeps both fields', () async {
    final source = await BackupService(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    final result = await BackupService(restored)
        .importJson(source, ownershipConfirmed: true);
    expect(result.conflicts, isEmpty);
    expect(result.inserted, greaterThan(0));

    final session = await restored.taskDao.getTaskById(sessionId);
    expect(session!.inboxItemId, openIdeaId);
    expect(session.inboxHistoryJson, '[]');
    final idea = await restored.taskDao.getTaskById(closedIdeaId);
    expect(idea!.inboxItemId, isNull);
    expect(
      TaskRepository.fromRow(idea).inboxHistory,
      TaskRepository.fromRow(
        (await database.taskDao.getTaskById(closedIdeaId))!,
      ).inboxHistory,
    );
    expect(
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(restored))['tasks'],
      ),
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(database))['tasks'],
      ),
    );
  });

  test('a replace round trip keeps both fields', () async {
    final source = await BackupService(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    final service = BackupService(restored);

    await service.replaceFromJson(
      source,
      preImportBackup: await service.exportJson(),
      confirmed: true,
      ownershipConfirmed: true,
    );

    expect(
      (await restored.taskDao.getTaskById(sessionId))!.inboxItemId,
      openIdeaId,
    );
    expect(
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(restored))['tasks'],
      ),
      BackupCodec.canonicalJson(
        (await BackupCodec.exportData(database))['tasks'],
      ),
    );
  });

  test('a v7 document imports with the defaults', () async {
    final document = await exported();
    for (final raw in dataOf(document)['tasks'] as List) {
      final row = raw as Map<String, dynamic>;
      row.remove('inbox_item_id');
      row.remove('inbox_history');
    }
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    final result = await BackupService(restored)
        .importJson(reseal(document, version: 7), ownershipConfirmed: true);

    expect(result.conflicts, isEmpty);
    final rows = await restored.select(restored.tasks).get();
    expect(rows, hasLength(4));
    for (final row in rows) {
      expect(row.inboxItemId, isNull, reason: row.id);
      expect(row.inboxHistoryJson, '[]', reason: row.id);
    }
  });

  test(
    'a session whose idea differs locally is blocked, not inserted',
    () async {
      final source = await BackupService(database).exportJson();
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      // The same id, but a different local row: the idea is a conflict.
      await target
          .into(target.tasks)
          .insert(
            TasksCompanion.insert(
              id: openIdeaId,
              title: 'A different local idea',
              isInbox: const Value(true),
              inboxContentVersion: const Value(1),
              createdAt: created,
              updatedAt: created,
            ),
          );

      final result = await BackupService(target)
          .importJson(source, ownershipConfirmed: true);

      expect(
        result.conflicts,
        contains(
          isA<BackupConflict>()
              .having((c) => c.id, 'id', sessionId)
              .having((c) => c.kind, 'kind', BackupConflictKind.blocked),
        ),
      );
      expect(await target.taskDao.getTaskById(sessionId), isNull);
      expect(
        (await target.taskDao.getTaskById(openIdeaId))!.title,
        'A different local idea',
      );
      // A task that does not depend on the conflicting idea still arrives.
      expect(await target.taskDao.getTaskById(secondSessionId), isNotNull);
    },
  );

  test(
    'M1: history on a row that is not an Inbox idea is accepted and kept',
    () async {
      // An older build converted an idea in place; the stored history stays on
      // the Day block (plan 4.1: sync and backup rows are checked for shape).
      final document = await exported();
      final history = [
        {
          'kind': 'closed',
          'at': '2026-10-12T09:30:00.000Z',
          'reason': 'Not needed',
          'experiment_id': null,
          'reopened_at': '2026-10-13T09:30:00.000Z',
        },
      ];
      taskRow(dataOf(document), sessionId)['inbox_history'] = history;
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      final result = await BackupService(target)
          .importJson(reseal(document), ownershipConfirmed: true);

      expect(result.conflicts, isEmpty);
      final row = await target.taskDao.getTaskById(sessionId);
      expect(row!.isInbox, isFalse);
      expect(
        TaskRepository.fromRow(row).inboxHistory.single.reason,
        'Not needed',
      );
    },
  );

  group('invalid rows are rejected before any write', () {
    Future<void> expectRejected(
      void Function(Map<String, dynamic> data) mutate,
    ) async {
      final document = await exported();
      mutate(dataOf(document));
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await expectLater(
        BackupService(target)
            .importJson(reseal(document), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await target.select(target.tasks).get(), isEmpty);
    }

    Map<String, Object?> event({
      String kind = 'closed',
      Object? reason = 'Not needed',
      Object? experimentId,
      Object? reopenedAt,
      Map<String, Object?> extra = const {},
    }) => {
      'kind': kind,
      'at': '2026-10-12T09:30:00.000Z',
      'reason': reason,
      'experiment_id': experimentId,
      'reopened_at': reopenedAt,
      ...extra,
    };

    test('a session whose idea is not in the document', () async {
      await expectRejected(
        (data) => taskRow(data, sessionId)['inbox_item_id'] =
            '00000000-0000-4000-8000-0000000000ff',
      );
    });

    test('a session that points at itself', () async {
      await expectRejected(
        (data) => taskRow(data, sessionId)['inbox_item_id'] = sessionId,
      );
    });

    test('an Inbox idea that is also a session', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_item_id'] = closedIdeaId,
      );
    });

    test('a link that is not an id', () async {
      await expectRejected(
        (data) => taskRow(data, sessionId)['inbox_item_id'] = 'not-an-id',
      );
    });

    // Changed with M1: well-formed history on a row that is not an Inbox idea
    // is no longer refused (see the test above this group). Its shape is still
    // checked.
    test('malformed history on a row that is not an Inbox idea', () async {
      await expectRejected(
        (data) => taskRow(data, sessionId)['inbox_history'] = [
          event(extra: {'note': 'x'}),
        ],
      );
      await expectRejected(
        (data) => taskRow(data, sessionId)['inbox_history'] = [
          event(reason: '  padded  '),
        ],
      );
    });

    test('history that is not an array', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = '[]',
      );
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = {},
      );
    });

    test('an event with an unknown key', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = [
          event(extra: {'note': 'x'}),
        ],
      );
    });

    test('a closed event without a reason, or with a blank one', () async {
      await expectRejected(
        (data) =>
            taskRow(data, openIdeaId)['inbox_history'] = [event(reason: null)],
      );
      await expectRejected(
        (data) =>
            taskRow(data, openIdeaId)['inbox_history'] = [event(reason: '   ')],
      );
    });

    test('a reason over 200 code points', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = [
          event(reason: '😀' * 201),
        ],
      );
    });

    test('an experiment event with a reason or without an id', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = [
          event(
            kind: 'experiment',
            reason: 'why',
            experimentId: 'experiment:x',
          ),
        ],
      );
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = [
          event(kind: 'experiment', reason: null),
        ],
      );
    });

    test('a still-closed event that is not the last', () async {
      await expectRejected(
        (data) =>
            taskRow(data, openIdeaId)['inbox_history'] = [event(), event()],
      );
    });

    test('events out of order', () async {
      await expectRejected(
        (data) => taskRow(data, openIdeaId)['inbox_history'] = [
          event(reopenedAt: '2026-10-12T10:00:00.000Z'),
          {...event(), 'at': '2026-10-11T09:30:00.000Z'},
        ],
      );
    });
  });
}
