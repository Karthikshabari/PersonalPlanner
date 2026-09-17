import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/database/daos/sync_dao.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/task_editor/domain/plan_title_history.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('all synchronized row updates preserve server versions', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'category',
                name: 'Work',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: 'tag',
                name: 'important',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: 'rule',
                rrule: 'FREQ=DAILY',
                taskTitle: 'Recurring',
                durationMin: 30,
                startTimeOfDay: '09:00',
                startDate: '2026-01-01',
                categoryId: const Value('category'),
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'task',
                title: 'Task',
                categoryId: const Value('category'),
                recurringRuleId: const Value('rule'),
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.taskTemplates)
            .insert(
              TaskTemplatesCompanion.insert(
                id: 'template',
                name: 'Template',
                durationMin: 30,
                categoryId: const Value('category'),
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.dailyReviews)
            .insert(
              DailyReviewsCompanion.insert(
                id: 'daily',
                date: '2026-01-01',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.weeklyReviews)
            .insert(
              WeeklyReviewsCompanion.insert(
                id: 'weekly',
                weekStartDate: '2025-12-29',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.subtasks)
            .insert(
              SubtasksCompanion.insert(
                id: 'subtask',
                taskId: 'task',
                title: 'Subtask',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.taskTags)
            .insert(
              TaskTagsCompanion.insert(
                taskId: 'task',
                tagId: 'tag',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
        await db
            .into(db.timerSessions)
            .insert(
              TimerSessionsCompanion.insert(
                id: 'timer',
                taskId: 'task',
                startedAt: now,
                endedAt: Value(now),
                state: const Value('finished'),
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(10),
              ),
            );
      });

      await db.categoryDao.updateCategory(
        (await db.categoryDao.getCategoryById('category'))!
            .copyWith(name: 'Updated Work'),
      );
      await db.tagDao.updateTag(
        (await db.tagDao.getTagById('tag'))!.copyWith(name: 'urgent'),
      );
      await db.recurringRuleDao.updateRule(
        (await db.recurringRuleDao.getRuleById('rule'))!
            .copyWith(taskTitle: 'Updated recurring'),
      );
      await db.taskDao.updateTask(
        (await db.taskDao.getTaskById('task'))!.copyWith(title: 'Updated task'),
      );
      await db.templateDao.updateTemplate(
        (await db.templateDao.getTemplateById('template'))!
            .copyWith(name: 'Updated template'),
      );
      await db.reviewDao.updateDailyReview(
        (await db.reviewDao.getDailyReviewById('daily'))!
            .copyWith(reflection: const Value('Updated daily')),
      );
      await db.reviewDao.updateWeeklyReview(
        (await db.reviewDao.getWeeklyReviewById('weekly'))!
            .copyWith(reflection: const Value('Updated weekly')),
      );
      await db.subtaskDao.updateSubtask(
        (await db.subtaskDao.getSubtaskById('subtask'))!
            .copyWith(title: 'Updated subtask'),
      );
      await (db.update(db.taskTags)..where(
            (row) => row.taskId.equals('task') & row.tagId.equals('tag'),
          ))
          .write(
            TaskTagsCompanion(
              updatedAt: Value(now.add(const Duration(minutes: 1))),
            ),
          );
      await db.timerDao.updateSession(
        (await db.timerDao.getSessionById('timer'))!.copyWith(durationSec: 60),
      );

      expect(
        (await db.categoryDao.getCategoryById('category'))!.serverVersion,
        10,
      );
      expect((await db.tagDao.getTagById('tag'))!.serverVersion, 10);
      expect(
        (await db.recurringRuleDao.getRuleById('rule'))!.serverVersion,
        10,
      );
      expect((await db.taskDao.getTaskById('task'))!.serverVersion, 10);
      expect(
        (await db.templateDao.getTemplateById('template'))!.serverVersion,
        10,
      );
      expect(
        (await db.reviewDao.getDailyReviewById('daily'))!.serverVersion,
        10,
      );
      expect(
        (await db.reviewDao.getWeeklyReviewById('weekly'))!.serverVersion,
        10,
      );
      expect(
        (await db.subtaskDao.getSubtaskById('subtask'))!.serverVersion,
        10,
      );
      expect(
        (await (db.select(db.taskTags)..where(
                  (row) => row.taskId.equals('task') & row.tagId.equals('tag'),
                ))
                .getSingle())
            .serverVersion,
        10,
      );
      expect((await db.timerDao.getSessionById('timer'))!.serverVersion, 10);
    } finally {
      await db.close();
    }
  });

  test('push preserves the expected token and strips server fields', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    try {
      final created = await CategoryRepository(db).insertCategory(
        Category(
          id: 'category-push',
          name: 'Work',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final initial = (await db.select(db.syncLog).get()).single;
      await db.syncDao.markAcknowledged(
        initial.operationId,
        DateTime.utc(2026, 1, 1),
      );
      await db.syncDao.runWithoutOutbound(() async {
        await db.customStatement(
          "UPDATE categories SET server_version = 7, sync_status = 0 WHERE id = ?",
          [created.id],
        );
      });

      await CategoryRepository(db)
          .updateCategory(created.copyWith(name: 'Updated Work'));
      final pending = (await db.syncDao.getRetryableOperations(
        DateTime.utc(2026, 1, 2),
      )).last;
      expect(pending.expectedServerVersion, 7);

      await SyncRepository.withGateway(db, gateway, 'account').push();
      expect(gateway.expectedVersions, [7]);
      expect(gateway.payloadVersions, [2]);
      expect(gateway.payloads.single.containsKey('server_version'), isFalse);
      expect(
        gateway.payloads.single.containsKey('_planner_payload_version'),
        isFalse,
      );
      expect(
        (await db.categoryDao.getCategoryById(created.id))!.serverVersion,
        8,
      );
    } finally {
      await db.close();
    }
  });

  test('v2 push pauses when the server lacks Inbox capabilities', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway()
      ..capabilities = const {
        'protocol_version': 1,
        'payload_versions': [1],
      };
    try {
      await CategoryRepository(db).insertCategory(
        Category(
          id: 'capability-gated-category',
          name: 'Work',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        'capability-gated-category',
      )).single;
      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).push();
      expect(failure?.kind, SyncFailureKind.permanent);
      expect(failure?.message, contains('Server upgrade required'));
      expect(gateway.payloads, isEmpty);
      expect(
        (await db.syncDao.getOperation(operation.operationId))?.state,
        'error',
      );
    } finally {
      await db.close();
    }
  });

  test('v2 push requires every canonical Foundation capability', () async {
    final requiredCapabilities = <String>[
      'schedule_duration_projection',
      'inbox_content_version',
      'due_date',
      'plan_title_history',
      'manual_actual_source',
      'timer_state_machine',
      'day_contexts',
      'recurrence_removal_provenance',
    ];
    for (final missing in requiredCapabilities) {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      try {
        gateway.capabilities = Map<String, dynamic>.from(gateway.capabilities)
          ..remove(missing);
        await CategoryRepository(db).insertCategory(
          Category(
            id: 'capability-$missing',
            name: missing,
            colorHex: '#4285F4',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        expect(failure?.kind, SyncFailureKind.permanent, reason: missing);
        expect(gateway.payloads, isEmpty, reason: missing);
        final operations = await db.select(db.syncLog).get();
        expect(operations.single.state, 'error', reason: missing);
      } finally {
        await db.close();
      }
    }
  });

  test('unsupported durable payload versions remain repairable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    try {
      await CategoryRepository(db).insertCategory(
        Category(
          id: 'unsupported-payload-category',
          name: 'Work',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final operation = (await db.syncDao.getRetryableOperations(
        DateTime.now(),
      )).single;
      await db.customStatement(
        'UPDATE sync_log SET payload = ? WHERE operation_id = ?',
        [
          jsonEncode({'_planner_payload_version': 3}),
          operation.operationId,
        ],
      );
      final failure = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).push();
      expect(failure?.kind, SyncFailureKind.invalidData);
      expect(
        failure?.message,
        contains('Unsupported local sync payload version'),
      );
      expect(
        (await db.syncDao.getOperation(operation.operationId))?.state,
        'error',
      );
      expect(gateway.payloads, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('push reloads queued edits after the create acknowledgement', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      final created = await CategoryRepository(db).insertCategory(
        Category(
          id: 'queued-edit-category',
          name: 'Before',
          colorHex: '#4285F4',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await CategoryRepository(db).updateCategory(
        created.copyWith(
          name: 'After',
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      );

      await SyncRepository.withGateway(db, gateway, 'account').push();

      expect(gateway.expectedVersions, [null, 8]);
      expect((await db.categoryDao.getCategoryById(created.id))!.name, 'After');
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test('account scope change abandons an in-flight push safely', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    var account = 'account-a';
    gateway.onApply = () => account = 'account-b';
    try {
      final created = await CategoryRepository(db).insertCategory(
        Category(
          id: 'account-switch-category',
          name: 'Private A data',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final result = await SyncRepository.withGateway(
        db,
        gateway,
        'account-a',
        currentAccountId: () => account,
      ).push();

      expect(result?.kind, SyncFailureKind.authentication);
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        created.id,
      )).single;
      expect(operation.state, 'pending');
      expect(
        (await db.categoryDao.getCategoryById(created.id))!.serverVersion,
        isNull,
      );
      expect((await db.categoryDao.getCategoryById(created.id))!.syncStatus, 1);
    } finally {
      await db.close();
    }
  });

  test('terminal sign-out abandons an in-flight push safely', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    String? account = 'account-a';
    gateway.onApply = () => account = null;
    try {
      final created = await CategoryRepository(db).insertCategory(
        Category(
          id: 'terminal-signout-category',
          name: 'Private A data',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final result = await SyncRepository.withGateway(
        db,
        gateway,
        'account-a',
        currentAccountId: () => account,
      ).push();

      expect(result?.kind, SyncFailureKind.authentication);
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        created.id,
      )).single;
      expect(operation.state, 'pending');
      expect(
        (await db.categoryDao.getCategoryById(created.id))!.serverVersion,
        isNull,
      );
    } finally {
      await db.close();
    }
  });

  test('account scope change abandons an in-flight pull safely', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    var account = 'account-a';
    gateway.onPull = () => account = 'account-b';
    gateway.pullPages.add([
      _categoryChange(
        changeId: 1,
        id: 'account-switch-remote',
        name: 'Private A remote data',
        now: DateTime.utc(2026, 1, 1),
      ),
    ]);
    try {
      final result = await SyncRepository.withGateway(
        db,
        gateway,
        'account-a',
        currentAccountId: () => account,
      ).pull();

      expect(result?.kind, SyncFailureKind.authentication);
      expect(await db.syncDao.getCursor('account-a'), 0);
      expect(
        await db.categoryDao.getCategoryById('account-switch-remote'),
        isNull,
      );
    } finally {
      await db.close();
    }
  });

  test('sync preserves a push failure when pull succeeds', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway()..applyError = StateError('network timeout');
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await CategoryRepository(db).insertCategory(
        Category(
          id: 'push-failure-category',
          name: 'Work',
          colorHex: '#4285F4',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await SyncRepository.withGateway(
        db,
        gateway,
        'account',
      ).sync();

      expect(result.pushFailure?.kind, SyncFailureKind.retryable);
      expect(result.pullFailure, isNull);
      expect(result.succeeded, isFalse);
      expect((await db.select(db.syncLog).get()).single.state, 'error');
    } finally {
      await db.close();
    }
  });

  test(
    'an unreachable backend never parks queued work as a permanent failure',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway()
        ..applyError = Exception(
          "ClientException with SocketException: Failed host lookup: "
          "'abcdefghijklmnopqrst.supabase.co'",
        );
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        await CategoryRepository(db).insertCategory(
          Category(
            id: 'backend-gone-category',
            name: 'Work',
            colorHex: '#4285F4',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).sync();

        expect(result.pushFailure?.kind, SyncFailureKind.backendUnavailable);
        expect(result.pushFailure?.keepsOperationQueued, isTrue);
        final operation = (await db.select(db.syncLog).get()).single;
        expect(operation.state, 'error');
        expect(operation.lastError, cloudBackendUnreachableMessage);
        // The entry stays eligible for the ordinary backoff retry: it is not
        // parked on the permanent-retry sentinel, and no local row was touched.
        expect(
          (await db.syncDao.getRetryableOperations(
            DateTime.now().toUtc().add(const Duration(minutes: 5)),
          )).map((row) => row.operationId),
          contains(operation.operationId),
        );
        expect(
          operation.nextAttemptAt,
          isNot(SyncDao.permanentRetryAt.toIso8601String()),
        );
        expect(
          await db.categoryDao.getCategoryById('backend-gone-category'),
          isNotNull,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'malformed remote changes are quarantined and advance the cursor',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'malformed-change',
          'payload': <Object?>[],
        },
      ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result?.kind, SyncFailureKind.invalidData);
        expect(await db.syncDao.getCursor('account'), 1);
        final quarantine = jsonDecode(
          (await db.syncDao.getSetting('sync.quarantine.account.1'))!,
        ) as Map<String, dynamic>;
        expect(quarantine['diagnostic'], isNotEmpty);
        expect((quarantine['raw_change'] as Map)['payload'], isA<List>());
        expect(await db.select(db.categories).get(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test('pulled domain rows refresh an already-open Drift stream', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    gateway.pullPages.add([
      _categoryChange(
        changeId: 1,
        id: 'stream-category',
        name: 'Remote Work',
        now: now,
      ),
    ]);
    try {
      final streamExpectation = expectLater(
        db.categoryDao.watchActiveCategories(),
        emitsInOrder([
          isEmpty,
          contains(
            isA<CategoryRow>().having((row) => row.id, 'id', 'stream-category'),
          ),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await SyncRepository.withGateway(db, gateway, 'account').pull();
      await streamExpectation;
    } finally {
      await db.close();
    }
  });

  test('day contexts round trip through remote pull and local push', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final remoteDate = '2026-01-03';
    final now = DateTime.utc(2026, 1, 1, 9);
    final remoteId = generateDeterministicUuid('day-context:$remoteDate');
    gateway.pullPages.add([
      _dayContextChange(
        changeId: 4,
        date: remoteDate,
        kind: 'travel',
        now: now,
      ),
    ]);
    try {
      final sync = SyncRepository.withGateway(db, gateway, 'account');
      await sync.pull();

      final remote = await DayContextRepository(db)
          .watchForDate(remoteDate)
          .first;
      expect(remote?.id, remoteId);
      expect(remote?.kind, DayContextKind.travel);
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(
        (await db.select(db.syncLog).get()),
        isEmpty,
        reason: 'remote context application must not echo to the outbox',
      );

      final localDate = '2026-01-04';
      final local = await DayContextRepository(db)
          .save(localDate, DayContextKind.custom, 'Family visit');
      final pending = await db.syncDao.getActiveOperationsForRecord(
        'day_contexts',
        local.id,
      );
      expect(pending, hasLength(1));
      expect(jsonDecode(pending.single.payload)['date'], localDate);

      await sync.push();
      expect(gateway.appliedTables, contains('day_contexts'));
      expect(await db.syncDao.pendingCount(), 0);
      final localRow = await (db.select(
        db.dayContexts,
      )..where((row) => row.id.equals(local.id))).getSingle();
      expect(localRow.serverVersion, 8);
    } finally {
      await db.close();
    }
  });

  test('local domain writes refresh an already-open outbox stream', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final streamExpectation = expectLater(
        db.syncDao.watchPendingOperations(),
        emitsInOrder([isEmpty, hasLength(1)]),
      );
      await Future<void>.delayed(Duration.zero);
      await CategoryRepository(db).insertCategory(
        Category(
          id: 'outbox-stream-category',
          name: 'Work',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1, 9),
          updatedAt: DateTime.utc(2026, 1, 1, 9),
        ),
      );
      await streamExpectation;
    } finally {
      await db.close();
    }
  });

  test(
    'remote offset timestamps use canonical UTC text for day queries',
    () async {
      PlannerTimeZone.initialize(identifier: 'UTC');
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'remote-offset-task',
          'table_name': 'tasks',
          'record_id': 'remote-offset-task',
          'operation': 'insert',
          'server_version': 1,
          'server_timestamp': '2026-09-02T00:00:00+00:00',
          'payload': {
            'id': 'remote-offset-task',
            'title': 'Offset midnight',
            'description': null,
            'start_time': '2026-09-02T00:00:00+00:00',
            'end_time': '2026-09-02T01:00:00+00:00',
            'estimated_duration_min': 60,
            'actual_duration_min': null,
            'manual_duration_adjustment_min': 0,
            'category_id': null,
            'priority': 0,
            'status': 'planned',
            'notes': null,
            'recurring_rule_id': null,
            'rescheduled_from_id': null,
            'rescheduled_to_id': null,
            'is_inbox': 0,
            'missed_at': null,
            'created_at': '2026-09-01T23:00:00+00:00',
            'updated_at': '2026-09-02T00:00:00+00:00',
            'deleted_at': null,
          },
        },
      ]);
      try {
        await SyncRepository.withGateway(db, gateway, 'account').pull();

        final row = await db.taskDao.getTaskById('remote-offset-task');
        expect(row, isNotNull);
        expect(row!.startTime!.toUtc(), DateTime.utc(2026, 9, 2));
        expect(
          await db.taskDao.getTasksForDay(DateTime.utc(2026, 9, 1)),
          isEmpty,
        );
        expect(
          (await db.taskDao.getTasksForDay(DateTime.utc(2026, 9, 2)))
              .map((task) => task.id),
          contains('remote-offset-task'),
        );
        final stored = await db
            .customSelect(
              'SELECT start_time FROM tasks WHERE id = ?',
              variables: [Variable<String>('remote-offset-task')],
            )
            .getSingle();
        expect(stored.read<String>('start_time'), '2026-09-02T00:00:00.000Z');
      } finally {
        await db.close();
      }
    },
  );

  test(
    'complete remote tombstone is materialized when the row is missing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'remote-task-delete',
          'table_name': 'tasks',
          'record_id': 'deleted-task',
          'operation': 'delete',
          'server_version': 4,
          'server_timestamp': now.toIso8601String(),
          'payload': {
            'id': 'deleted-task',
            'title': 'Historical task',
            'description': null,
            'start_time': null,
            'end_time': null,
            'estimated_duration_min': 30,
            'actual_duration_min': null,
            'manual_duration_adjustment_min': 0,
            'category_id': null,
            'priority': 0,
            'status': 'cancelled',
            'notes': null,
            'recurring_rule_id': null,
            'rescheduled_from_id': null,
            'rescheduled_to_id': null,
            'is_inbox': 0,
            'missed_at': null,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'deleted_at': now.add(const Duration(minutes: 1)).toIso8601String(),
          },
        },
      ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result, isNull);
        final row = await db.taskDao.getTaskById('deleted-task');
        expect(row, isNotNull);
        expect(row!.deletedAt, isNotNull);
        expect(row.serverVersion, 4);
        expect(await db.syncDao.getCursor('account'), 1);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'timer close and replacement start in one page are applied in order',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'timer-task',
                title: 'Timer task',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.timerSessions)
            .insert(
              TimerSessionsCompanion.insert(
                id: 'timer-one',
                taskId: 'timer-task',
                startedAt: now,
                state: const Value('running'),
                runningSince: Value(now),
                createdAt: now,
                updatedAt: now,
              ),
            );
      });
      final ended = now.add(const Duration(minutes: 25));
      Map<String, dynamic> timerPayload(
        String id,
        DateTime started, {
        DateTime? endedAt,
      }) => {
        'id': id,
        'task_id': 'timer-task',
        'started_at': started.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'duration_sec': endedAt == null ? 0 : 1500,
        'created_at': started.toIso8601String(),
        'updated_at': (endedAt ?? started).toIso8601String(),
        'deleted_at': null,
      };
      gateway.pullPages.add([
        {
          'change_id': 2,
          'operation_id': 'remote-timer-close',
          'table_name': 'timer_sessions',
          'record_id': 'timer-one',
          'operation': 'update',
          'server_version': 2,
          'server_timestamp': ended.toIso8601String(),
          'payload': timerPayload('timer-one', now, endedAt: ended),
        },
        {
          'change_id': 3,
          'operation_id': 'remote-timer-start',
          'table_name': 'timer_sessions',
          'record_id': 'timer-two',
          'operation': 'insert',
          'server_version': 3,
          'server_timestamp': ended.toIso8601String(),
          'payload': timerPayload('timer-two', ended),
        },
      ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result, isNull);
        expect(
          (await db.timerDao.getSessionById('timer-one'))!.endedAt,
          isNotNull,
        );
        expect(
          (await db.timerDao.getSessionById('timer-one'))!.endedAt!
              .isAtSameMomentAs(ended),
          isTrue,
        );
        expect(
          (await db.timerDao.getSessionById('timer-two'))!.endedAt,
          isNull,
        );
        expect(await db.syncDao.getCursor('account'), 3);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'pull recomputes a task actual cache after its full timer source page',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: 'actual-source-task',
                  title: 'Actual source',
                  actualDurationMin: const Value(10),
                  manualDurationAdjustmentMin: const Value(10),
                  manualActualSet: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        });
        final ended = now.add(const Duration(minutes: 20));
        gateway.pullPages.add([
          {
            'change_id': 1,
            'operation_id': 'remote-finished-source',
            'table_name': 'timer_sessions',
            'record_id': 'remote-finished-source',
            'operation': 'insert',
            'server_version': 1,
            'server_timestamp': ended.toIso8601String(),
            'payload': {
              'id': 'remote-finished-source',
              'task_id': 'actual-source-task',
              'started_at': now.toIso8601String(),
              'ended_at': ended.toIso8601String(),
              'duration_sec': 1200,
              'state': 'finished',
              'running_since': null,
              'work_intervals_json': jsonEncode([
                {
                  'start_at': now.toIso8601String(),
                  'end_at': ended.toIso8601String(),
                  'duration_sec': 1200,
                },
              ]),
              'owner_device_id': '11111111-1111-4111-8111-111111111111',
              'created_at': now.toIso8601String(),
              'updated_at': ended.toIso8601String(),
              'deleted_at': null,
            },
          },
        ]);

        expect(
          await SyncRepository.withGateway(db, gateway, 'account').pull(),
          isNull,
        );
        final task = await db.taskDao.getTaskById('actual-source-task');
        expect(task?.actualDurationMin, 30);
        await SyncRepository.withGateway(db, gateway, 'account').pull();
        expect(
          (await db.taskDao.getTaskById('actual-source-task'))
              ?.actualDurationMin,
          30,
        );
      } finally {
        await db.close();
      }
    },
  );

  test('push orders parent upserts before child upserts', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'ordered-category',
              name: 'Work',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'ordered-tag',
              name: 'important',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'ordered-task',
              title: 'Task',
              categoryId: const Value('ordered-category'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.subtasks)
          .insert(
            SubtasksCompanion.insert(
              id: 'ordered-subtask',
              taskId: 'ordered-task',
              title: 'Subtask',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.taskTags)
          .insert(
            TaskTagsCompanion.insert(
              taskId: 'ordered-task',
              tagId: 'ordered-tag',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await SyncRepository.withGateway(db, gateway, 'account').push();

      expect(gateway.appliedTables, [
        'categories',
        'tags',
        'tasks',
        'subtasks',
        'task_tags',
      ]);
      expect(await db.syncDao.pendingCount(), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'pull drains pages and advances the cursor after each committed page',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      gateway.pullPages.add([
        for (var i = 1; i <= 200; i++)
          _categoryChange(
            changeId: i,
            id: 'remote-$i',
            name: 'Remote $i',
            now: now,
          ),
      ]);
      gateway.pullPages.add([
        _categoryChange(
          changeId: 201,
          id: 'remote-201',
          name: 'Remote 201',
          now: now,
        ),
      ]);
      try {
        await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull(limit: 200);

        expect(gateway.pullCursors, [0, 200]);
        expect((await db.select(db.categories).get()).length, 201);
        expect(await db.syncDao.getCursor('account'), 201);
        expect(await db.syncDao.pendingCount(), 0);
      } finally {
        await db.close();
      }
    },
  );

  test('pull orders a child before its out-of-order parent feed entry is committed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    gateway.pullPages.add([
      {
        'change_id': 1,
        'operation_id': 'remote-subtask-1',
        'table_name': 'subtasks',
        'record_id': 'remote-subtask',
        'operation': 'insert',
        'server_version': 1,
        'server_timestamp': now.toIso8601String(),
        'payload': {
          'id': 'remote-subtask',
          'task_id': 'remote-task',
          'title': 'Child',
          'is_completed': 0,
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'deleted_at': null,
        },
      },
      {
        'change_id': 2,
        'operation_id': 'remote-task-2',
        'table_name': 'tasks',
        'record_id': 'remote-task',
        'operation': 'insert',
        'server_version': 2,
        'server_timestamp': now.toIso8601String(),
        'payload': {
          'id': 'remote-task',
          'title': 'Parent',
          'description': null,
          'start_time': null,
          'end_time': null,
          'estimated_duration_min': null,
          'actual_duration_min': null,
          'manual_duration_adjustment_min': 0,
          'category_id': null,
          'priority': 0,
          'status': 'planned',
          'notes': null,
          'recurring_rule_id': null,
          'rescheduled_from_id': null,
          'rescheduled_to_id': null,
          'is_inbox': 0,
          'missed_at': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'deleted_at': null,
        },
      },
    ]);
    try {
      await SyncRepository.withGateway(db, gateway, 'account').pull();

      expect((await db.taskDao.getTaskById('remote-task'))?.title, 'Parent');
      expect(
        (await db.subtaskDao.getSubtaskById('remote-subtask'))?.taskId,
        'remote-task',
      );
      expect(await db.syncDao.getCursor('account'), 2);
    } finally {
      await db.close();
    }
  });

  test(
    'pull accepts reciprocal reschedule history without a dependency cycle',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      Map<String, dynamic> taskPayload(String id, {String? from, String? to}) =>
          {
            'id': id,
            'title': id,
            'description': null,
            'start_time': null,
            'end_time': null,
            'estimated_duration_min': null,
            'actual_duration_min': null,
            'manual_duration_adjustment_min': 0,
            'category_id': null,
            'priority': 0,
            'status': 'rescheduled',
            'notes': null,
            'recurring_rule_id': null,
            'rescheduled_from_id': from,
            'rescheduled_to_id': to,
            'is_inbox': 0,
            'missed_at': null,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'deleted_at': null,
          };
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'remote-reschedule-a',
          'table_name': 'tasks',
          'record_id': 'reschedule-a',
          'operation': 'insert',
          'server_version': 1,
          'server_timestamp': now.toIso8601String(),
          'payload': taskPayload('reschedule-a', to: 'reschedule-b'),
        },
        {
          'change_id': 2,
          'operation_id': 'remote-reschedule-b',
          'table_name': 'tasks',
          'record_id': 'reschedule-b',
          'operation': 'insert',
          'server_version': 2,
          'server_timestamp': now.toIso8601String(),
          'payload': taskPayload('reschedule-b', from: 'reschedule-a'),
        },
      ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result, isNull);
        expect(
          (await db.taskDao.getTaskById('reschedule-a'))!.rescheduledToId,
          'reschedule-b',
        );
        expect(
          (await db.taskDao.getTaskById('reschedule-b'))!.rescheduledFromId,
          'reschedule-a',
        );
        expect(await db.syncDao.getCursor('account'), 2);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'pull retains a tombstoned task before its historical timer child',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final started = DateTime.utc(2026, 1, 1, 9);
      final ended = started.add(const Duration(minutes: 30));
      Map<String, dynamic> taskPayload({String? deletedAt}) => {
        'id': 'deleted-parent',
        'title': 'Completed history',
        'description': null,
        'start_time': null,
        'end_time': null,
        'estimated_duration_min': null,
        'actual_duration_min': null,
        'manual_duration_adjustment_min': 0,
        'category_id': null,
        'priority': 0,
        'status': 'completed',
        'notes': null,
        'recurring_rule_id': null,
        'rescheduled_from_id': null,
        'rescheduled_to_id': null,
        'is_inbox': 0,
        'missed_at': null,
        'created_at': started.toIso8601String(),
        'updated_at': ended.toIso8601String(),
        'deleted_at': deletedAt,
      };
      gateway.pullPages.add([
        {
          'change_id': 1,
          'operation_id': 'parent-created',
          'table_name': 'tasks',
          'record_id': 'deleted-parent',
          'operation': 'insert',
          'server_version': 1,
          'server_timestamp': started.toIso8601String(),
          'payload': taskPayload(),
        },
        {
          'change_id': 2,
          'operation_id': 'historical-timer',
          'table_name': 'timer_sessions',
          'record_id': 'historical-timer',
          'operation': 'insert',
          'server_version': 2,
          'server_timestamp': ended.toIso8601String(),
          'payload': {
            'id': 'historical-timer',
            'task_id': 'deleted-parent',
            'started_at': started.toIso8601String(),
            'ended_at': ended.toIso8601String(),
            'duration_sec': 1800,
            'created_at': started.toIso8601String(),
            'updated_at': ended.toIso8601String(),
            'deleted_at': null,
          },
        },
        {
          'change_id': 3,
          'operation_id': 'parent-deleted',
          'table_name': 'tasks',
          'record_id': 'deleted-parent',
          'operation': 'delete',
          'server_version': 3,
          'server_timestamp': ended.toIso8601String(),
          'payload': taskPayload(deletedAt: ended.toIso8601String()),
        },
      ]);
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(result, isNull);
        expect(
          (await db.taskDao.getTaskById('deleted-parent'))!.deletedAt,
          isNotNull,
        );
        expect(await db.timerDao.getSessionById('historical-timer'), isNotNull);
        expect(await db.syncDao.getCursor('account'), 3);
      } finally {
        await db.close();
      }
    },
  );

  test('pulled acknowledgements rebase newer local writes without overwriting them', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'rebase-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(5),
              ),
            );
      });
      final repository = CategoryRepository(db);
      final original = (await repository.getCategoryById('rebase-category'))!;
      await repository.updateCategory(original.copyWith(name: 'First local'));
      final firstOperation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        original.id,
      )).single;
      await repository.updateCategory(original.copyWith(name: 'Second local'));
      gateway.pullPages.add([
        _categoryChange(
          changeId: 6,
          id: original.id,
          name: 'First local',
          operationId: firstOperation.operationId,
          now: now,
        ),
      ]);

      await SyncRepository.withGateway(db, gateway, 'account').pull();

      final row = (await repository.getCategoryById(original.id))!;
      final rowMetadata = (await db.categoryDao.getCategoryById(original.id))!;
      final operations = await db.syncDao.getActiveOperationsForRecord(
        'categories',
        original.id,
      );
      expect(row.name, 'Second local');
      expect(rowMetadata.serverVersion, 6);
      expect(rowMetadata.syncStatus, 1);
      expect(operations, hasLength(1));
      expect(operations.single.state, 'pending');
      expect(operations.single.expectedServerVersion, 6);
      expect(await db.syncDao.getCursor('account'), 6);
    } finally {
      await db.close();
    }
  });

  test(
    'coalescing a later feed change still records an earlier acknowledgement',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: 'coalesced-category',
                  name: 'Original',
                  colorHex: '#4285F4',
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
        });
        final repository = CategoryRepository(db);
        final original = (await repository.getCategoryById(
          'coalesced-category',
        ))!;
        await repository.updateCategory(
          original.copyWith(name: 'Acknowledged'),
        );
        final operation = (await db.syncDao.getActiveOperationsForRecord(
          'categories',
          original.id,
        )).single;
        gateway.pullPages.add([
          _categoryChange(
            changeId: 6,
            id: original.id,
            name: 'Acknowledged',
            operationId: operation.operationId,
            now: now,
          ),
          _categoryChange(
            changeId: 7,
            id: original.id,
            name: 'Later remote change',
            now: now,
          ),
        ]);

        await SyncRepository.withGateway(db, gateway, 'account').pull();

        final row = (await repository.getCategoryById(original.id))!;
        expect(row.name, 'Later remote change');
        expect(
          (await db.syncDao.getOperation(operation.operationId))!.state,
          'acknowledged',
        );
        expect(await db.syncDao.watchConflicts().first, isEmpty);
        expect(await db.syncDao.getCursor('account'), 7);
      } finally {
        await db.close();
      }
    },
  );

  test('competing pulled changes become explicit conflicts and preserve local data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'conflict-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(5),
              ),
            );
      });
      final repository = CategoryRepository(db);
      final original = (await repository.getCategoryById('conflict-category'))!;
      await repository.updateCategory(original.copyWith(name: 'Local name'));
      gateway.pullPages.add([
        _categoryChange(
          changeId: 6,
          id: original.id,
          name: 'Remote name',
          now: now,
        ),
      ]);

      await SyncRepository.withGateway(db, gateway, 'account').pull();

      final row = (await repository.getCategoryById(original.id))!;
      final rowMetadata = (await db.categoryDao.getCategoryById(original.id))!;
      final conflicts = await db.syncDao.watchConflicts().first;
      expect(row.name, 'Local name');
      expect(rowMetadata.serverVersion, 6);
      expect(rowMetadata.syncStatus, 2);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.actualServerVersion, 6);
      expect(
        jsonDecode(conflicts.single.remoteSnapshot)['name'],
        'Remote name',
      );
    } finally {
      await db.close();
    }
  });

  test('push conflict keeps the newest local snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'push-conflict-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(5),
              ),
            );
      });
      final repository = CategoryRepository(db);
      final original = (await repository.getCategoryById(
        'push-conflict-category',
      ))!;
      await repository.updateCategory(original.copyWith(name: 'First local'));
      final first = (await repository.getCategoryById(original.id))!;
      await repository.updateCategory(first.copyWith(name: 'Newest local'));
      final queuedRevisions =
          (await db.syncDao.getActiveOperationsForRecord(
                'categories',
                original.id,
              ))
              .map((entry) => jsonDecode(entry.payload)['_planner_revision'])
              .toList();
      expect(queuedRevisions, containsAll([2, 3]));
      gateway.responses.addAll([
        {
          'status': 'conflict',
          'server_version': 0,
          'change_id': 0,
          'actual_server_version': 6,
          'remote_snapshot': {'name': 'Remote'},
        },
        {
          'status': 'applied',
          'server_version': 7,
          'change_id': 1,
          'server_timestamp': now.toIso8601String(),
        },
      ]);

      await SyncRepository.withGateway(db, gateway, 'account').push();

      final conflict = (await db.syncDao.watchConflicts().first).single;
      expect(jsonDecode(conflict.localSnapshot)['name'], 'Newest local');
      expect(
        (await db.syncDao.getOperation(conflict.operationId))!.state,
        anyOf('acknowledged', 'conflict'),
      );
      expect(
        (await db.categoryDao.getCategoryById(original.id))!.syncStatus,
        2,
      );
    } finally {
      await db.close();
    }
  });

  test(
    'Keep Local resolves using an edit made after conflict capture',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 1, 1, 9);
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: 'keep-local-newer',
                  name: 'Base',
                  colorHex: '#4285F4',
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(1),
                ),
              );
        });
        final repository = SyncRepository.withGateway(db, gateway, 'account');
        final base = (await db.categoryDao.getCategoryById(
          'keep-local-newer',
        ))!;
        await db.categoryDao.updateCategory(base.copyWith(name: 'Local v1'));
        gateway.responses.add({
          'status': 'conflict',
          'server_version': 3,
          'change_id': 3,
          'server_timestamp': now.toIso8601String(),
          'actual_server_version': 2,
          'remote_snapshot': {
            'id': base.id,
            'name': 'Remote',
            'color_hex': '#4285F4',
            'sort_order': 0,
            'is_focus': 0,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'deleted_at': null,
          },
        });
        await repository.push();

        await db.categoryDao.updateCategory(
          (await db.categoryDao.getCategoryById(base.id))!
              .copyWith(name: 'Local v2'),
        );
        final conflict = (await db.syncDao.watchConflicts().first).single;
        await repository.keepLocal(conflict.id);

        final queued = await db.syncDao.getActiveOperationsForRecord(
          'categories',
          base.id,
        );
        expect(queued, hasLength(1));
        expect(jsonDecode(queued.single.payload)['name'], 'Local v2');
        expect(queued.single.expectedServerVersion, 2);
      } finally {
        await db.close();
      }
    },
  );

  test('Keep Local rebases against the remote version and Keep Remote applies tombstones', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _FakeGateway();
    final now = DateTime.utc(2026, 1, 1, 9);
    try {
      await db.syncDao.runWithoutOutbound(() async {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'resolution-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
                serverVersion: const Value(5),
              ),
            );
      });
      final repository = CategoryRepository(db);
      final original = (await repository.getCategoryById(
        'resolution-category',
      ))!;
      await repository.updateCategory(original.copyWith(name: 'Local name'));
      final sync = SyncRepository.withGateway(db, gateway, 'account');
      gateway.pullPages.add([
        _categoryChange(
          changeId: 6,
          id: original.id,
          name: 'Remote name',
          now: now,
        ),
      ]);
      await sync.pull();
      final conflict = (await db.syncDao.watchConflicts().first).single;

      await sync.keepLocal(conflict.id);
      final rebased = await db.syncDao.getActiveOperationsForRecord(
        'categories',
        original.id,
      );
      expect(rebased, hasLength(1));
      expect(rebased.single.operation, 'update');
      expect(rebased.single.expectedServerVersion, 6);
      expect(
        (await db.categoryDao.getCategoryById(original.id))!.syncStatus,
        1,
      );

      // Recreate a conflict using the rebased operation, then choose the
      // server tombstone. The old conflict operation must be retired and no
      // local echo may be produced.
      await db.syncDao.markConflict(rebased.single.operationId, now);
      await db.syncDao.insertConflict(
        SyncConflictsCompanion.insert(
          id: 'resolution-conflict-2',
          operationId: rebased.single.operationId,
          entityTableName: 'categories',
          recordId: original.id,
          expectedServerVersion: const Value(6),
          actualServerVersion: const Value(7),
          localSnapshot: rebased.single.payload,
          remoteSnapshot: jsonEncode({
            'id': original.id,
            'name': 'Remote name',
            'color_hex': '#4285F4',
            'sort_order': 0,
            'is_focus': 0,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'deleted_at': now.toIso8601String(),
          }),
          createdAt: now,
        ),
      );
      await sync.keepRemote('resolution-conflict-2');

      final remoteRow = (await db.categoryDao.getCategoryById(original.id))!;
      expect(remoteRow.deletedAt, isNotNull);
      expect(remoteRow.serverVersion, 7);
      expect(remoteRow.syncStatus, 0);
      expect(await db.syncDao.pendingCount(), 0);
      expect(await db.syncDao.watchConflicts().first, isEmpty);
    } finally {
      await db.close();
    }
  });

  test(
    'concurrent title-history branch becomes a conflict instead of quarantine',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 9, 16, 9);
      const taskId = '00000000-0000-7000-8000-000000000101';
      const operationId = '00000000-0000-7000-8000-000000000102';
      final localEvent = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000103',
        previousTitle: 'Common title',
        newTitle: 'Local title',
        changedAt: now,
      );
      final localPayload = _taskPayload(
        id: taskId,
        title: 'Local title',
        history: [localEvent],
        displayPlanChangeId: localEvent.id,
        recurrenceRemovalReason: 'rule_excluded',
        now: now,
      );
      final remotePayload = _taskPayload(
        id: taskId,
        title: 'Common title',
        history: const [],
        displayPlanChangeId: null,
        now: now.add(const Duration(minutes: 1)),
      )..['notes'] = 'Remote-only note';
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: taskId,
                  title: 'Local title',
                  startTime: Value(now),
                  endTime: Value(now.add(const Duration(hours: 1))),
                  estimatedDurationMin: const Value(60),
                  recurrenceRemovalReason: const Value('rule_excluded'),
                  planTitleHistoryJson: Value(
                    PlanTitleHistory.encodeJson([localEvent]),
                  ),
                  displayPlanChangeId: Value(localEvent.id),
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              operation: 'update',
              expectedServerVersion: const Value(5),
              payload: jsonEncode(localPayload),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        });
        gateway.pullPages.add([
          _taskChange(
            changeId: 6,
            operationId: '00000000-0000-7000-8000-000000000104',
            payload: remotePayload,
            now: now,
          ),
        ]);

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(failure, isNull);
        final conflicts = await db.syncDao.watchConflicts().first;
        expect(conflicts, hasLength(1));
        expect(
          jsonDecode(conflicts.single.remoteSnapshot)['notes'],
          'Remote-only note',
        );
        expect(
          await db.syncDao.getSetting('sync.quarantine.account.6'),
          isNull,
        );
        final task = await db.taskDao.getTaskById(taskId);
        expect(task?.title, 'Local title');
        expect(task?.recurrenceRemovalReason, 'rule_excluded');
        expect(task?.planTitleHistoryJson, contains(localEvent.id));
      } finally {
        await db.close();
      }
    },
  );

  test(
    'immutable title event collision is quarantined, not conflicted',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 9, 16, 10);
      const taskId = '00000000-0000-7000-8000-000000000111';
      const operationId = '00000000-0000-7000-8000-000000000112';
      final localEvent = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000113',
        previousTitle: 'Common title',
        newTitle: 'Local title',
        changedAt: now,
      );
      final localPayload = _taskPayload(
        id: taskId,
        title: 'Local title',
        history: [localEvent],
        displayPlanChangeId: localEvent.id,
        now: now,
      );
      final remoteEvent = PlanTitleChange(
        id: localEvent.id,
        previousTitle: 'Common title',
        newTitle: 'Repurposed title',
        changedAt: now,
      );
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: taskId,
                  title: 'Local title',
                  startTime: Value(now),
                  endTime: Value(now.add(const Duration(hours: 1))),
                  estimatedDurationMin: const Value(60),
                  planTitleHistoryJson: Value(
                    PlanTitleHistory.encodeJson([localEvent]),
                  ),
                  displayPlanChangeId: Value(localEvent.id),
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              operation: 'update',
              expectedServerVersion: const Value(5),
              payload: jsonEncode(localPayload),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        });
        gateway.pullPages.add([
          _taskChange(
            changeId: 7,
            operationId: '00000000-0000-7000-8000-000000000114',
            payload: _taskPayload(
              id: taskId,
              title: 'Repurposed title',
              history: [remoteEvent],
              displayPlanChangeId: remoteEvent.id,
              now: now,
            ),
            now: now,
          ),
        ]);

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).pull();

        expect(failure?.kind, SyncFailureKind.invalidData);
        expect(await db.syncDao.watchConflicts().first, isEmpty);
        expect(
          await db.syncDao.getSetting('sync.quarantine.account.7'),
          isNotNull,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'old task acknowledgement on a page boundary preserves newer rename',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 9, 16, 11);
      const taskId = '00000000-0000-7000-8000-000000000121';
      const operationA = '00000000-0000-7000-8000-000000000122';
      const operationB = '00000000-0000-7000-8000-000000000123';
      final eventA = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000124',
        previousTitle: 'Common title',
        newTitle: 'First rename',
        changedAt: now,
      );
      final eventB = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000125',
        previousTitle: 'First rename',
        newTitle: 'Newest rename',
        changedAt: now.add(const Duration(minutes: 1)),
      );
      final payloadA = _taskPayload(
        id: taskId,
        title: 'First rename',
        history: [eventA],
        displayPlanChangeId: eventA.id,
        now: now,
      );
      final payloadB = _taskPayload(
        id: taskId,
        title: 'Newest rename',
        history: [eventA, eventB],
        displayPlanChangeId: eventB.id,
        now: now.add(const Duration(minutes: 1)),
      );
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: taskId,
                  title: 'Newest rename',
                  startTime: Value(now),
                  endTime: Value(now.add(const Duration(hours: 1))),
                  estimatedDurationMin: const Value(60),
                  planTitleHistoryJson: Value(
                    PlanTitleHistory.encodeJson([eventA, eventB]),
                  ),
                  displayPlanChangeId: Value(eventB.id),
                  createdAt: now,
                  updatedAt: now.add(const Duration(minutes: 1)),
                  serverVersion: const Value(5),
                ),
              );
          for (final entry in [
            (operationA, payloadA, now),
            (operationB, payloadB, now.add(const Duration(minutes: 1))),
          ]) {
            await db.syncDao.enqueueOperation(
              SyncLogCompanion.insert(
                operationId: entry.$1,
                entityTableName: 'tasks',
                recordId: taskId,
                operation: 'update',
                expectedServerVersion: const Value(5),
                payload: jsonEncode(entry.$2),
                state: const Value('pending'),
                createdAt: entry.$3,
                updatedAt: entry.$3,
              ),
            );
          }
        });
        gateway.pullPages.addAll([
          [
            _taskChange(
              changeId: 8,
              operationId: operationA,
              payload: payloadA,
              now: now,
            ),
          ],
          const <Object?>[],
        ]);

        await SyncRepository.withGateway(db, gateway, 'account').pull(limit: 1);

        final task = await db.taskDao.getTaskById(taskId);
        expect(task?.title, 'Newest rename');
        expect(task?.displayPlanChangeId, eventB.id);
        expect(
          PlanTitleHistory.decodeJson(task!.planTitleHistoryJson)
              .map((event) => event.id),
          orderedEquals([eventA.id, eventB.id]),
        );
        expect(
          (await db.syncDao.getOperation(operationA))?.state,
          'acknowledged',
        );
        final newer = await db.syncDao.getOperation(operationB);
        expect(newer?.state, 'pending');
        expect(newer?.expectedServerVersion, 8);
        expect(await db.syncDao.watchConflicts().first, isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'retained F03 quarantine repair is bounded and preserves current edits',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 9, 16, 12);
      const taskId = '00000000-0000-7000-8000-000000000131';
      const operationId = '00000000-0000-7000-8000-000000000132';
      final localEvent = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000133',
        previousTitle: 'Common title',
        newTitle: 'Current local title',
        changedAt: now,
      );
      final localPayload = _taskPayload(
        id: taskId,
        title: 'Current local title',
        history: [localEvent],
        displayPlanChangeId: localEvent.id,
        now: now,
      );
      final retained = _taskChange(
        changeId: 41,
        operationId: '00000000-0000-7000-8000-000000000134',
        payload: _taskPayload(
          id: taskId,
          title: 'Common title',
          history: const [],
          displayPlanChangeId: null,
          now: now,
        )..['notes'] = 'Retained remote note',
        now: now,
      );
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: taskId,
                  title: 'Current local title',
                  startTime: Value(now),
                  endTime: Value(now.add(const Duration(hours: 1))),
                  estimatedDurationMin: const Value(60),
                  planTitleHistoryJson: Value(
                    PlanTitleHistory.encodeJson([localEvent]),
                  ),
                  displayPlanChangeId: Value(localEvent.id),
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              operation: 'update',
              expectedServerVersion: const Value(5),
              payload: jsonEncode(localPayload),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        });
        await db.syncDao.recordQuarantinedChange(
          'account',
          41,
          'Rejected remote tasks/$taskId: Invalid sync data: '
              'Existing plan title events cannot be removed or changed.',
          rawChange: retained,
        );
        await db.syncDao.recordQuarantinedChange(
          'account',
          42,
          'Invalid sync data: malformed unrelated payload',
          rawChange: const {'payload': <Object>[]},
        );

        await SyncRepository.withGateway(db, _FakeGateway(), 'account').pull();

        expect(
          await db.syncDao.getSetting('sync.quarantine.account.41'),
          isNull,
        );
        expect(
          await db.syncDao.getSetting('sync.quarantine.account.42'),
          isNotNull,
        );
        expect(await db.syncDao.getCursor('account'), 0);
        final conflicts = await db.syncDao.watchConflicts().first;
        expect(conflicts, hasLength(1));
        expect(
          jsonDecode(conflicts.single.remoteSnapshot)['notes'],
          'Retained remote note',
        );
        final task = await db.taskDao.getTaskById(taskId);
        expect(task?.title, 'Current local title');
        expect(task?.planTitleHistoryJson, contains(localEvent.id));
      } finally {
        await db.close();
      }
    },
  );

  test(
    'task conflict choices retain the union of intentional title events',
    () async {
      Future<void> verifyChoice({required bool keepRemote}) async {
        final db = AppDatabase(NativeDatabase.memory());
        final now = DateTime.utc(2026, 9, 13, 10);
        const taskId = '00000000-0000-7000-8000-0000000000dd';
        final localEvent = PlanTitleChange(
          id: '00000000-0000-7000-8000-0000000000e1',
          previousTitle: 'Read book',
          newTitle: 'Office work',
          changedAt: now,
        );
        final remoteEvent = PlanTitleChange(
          id: '00000000-0000-7000-8000-0000000000e2',
          previousTitle: 'Office work',
          newTitle: 'Client call',
          changedAt: now.add(const Duration(minutes: 1)),
        );
        final newerLocalEvent = PlanTitleChange(
          id: '00000000-0000-7000-8000-0000000000e5',
          previousTitle: 'Office work',
          newTitle: 'Later local title',
          changedAt: now.add(const Duration(minutes: 2)),
        );
        final localPayload = _taskPayload(
          id: taskId,
          title: 'Office work',
          history: [localEvent],
          displayPlanChangeId: localEvent.id,
          now: now,
        );
        final remotePayload = _taskPayload(
          id: taskId,
          title: 'Client call',
          history: [remoteEvent],
          displayPlanChangeId: remoteEvent.id,
          now: now.add(const Duration(minutes: 1)),
        );
        const operationId = '00000000-0000-7000-8000-0000000000e3';
        const conflictId = '00000000-0000-7000-8000-0000000000e4';
        try {
          await db.syncDao.runWithoutOutbound(() async {
            await db
                .into(db.tasks)
                .insert(
                  TasksCompanion.insert(
                    id: taskId,
                    title: 'Office work',
                    startTime: Value(now),
                    endTime: Value(now.add(const Duration(hours: 1))),
                    estimatedDurationMin: const Value(60),
                    planTitleHistoryJson: Value(
                      PlanTitleHistory.encodeJson([localEvent]),
                    ),
                    displayPlanChangeId: Value(localEvent.id),
                    createdAt: now,
                    updatedAt: now,
                    serverVersion: const Value(5),
                  ),
                );
          });
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              operation: 'update',
              expectedServerVersion: const Value(5),
              payload: jsonEncode(localPayload),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
          await db.syncDao.markConflict(operationId, now);
          await db.syncDao.insertConflict(
            SyncConflictsCompanion.insert(
              id: conflictId,
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              expectedServerVersion: const Value(5),
              actualServerVersion: const Value(6),
              localSnapshot: jsonEncode(localPayload),
              remoteSnapshot: jsonEncode(remotePayload),
              createdAt: now,
            ),
          );
          if (keepRemote) {
            final newerLocalPayload = _taskPayload(
              id: taskId,
              title: 'Later local title',
              history: [localEvent, newerLocalEvent],
              displayPlanChangeId: newerLocalEvent.id,
              now: now.add(const Duration(minutes: 2)),
            );
            await db.syncDao.runWithoutOutbound(() async {
              await (db.update(
                db.tasks,
              )..where((row) => row.id.equals(taskId))).write(
                TasksCompanion(
                  title: const Value('Later local title'),
                  planTitleHistoryJson: Value(
                    newerLocalPayload['plan_title_history_json'] as String,
                  ),
                  displayPlanChangeId: Value(newerLocalEvent.id),
                  updatedAt: Value(now.add(const Duration(minutes: 2))),
                  revision: const Value(2),
                  syncStatus: const Value(1),
                ),
              );
              await db.syncDao.enqueueOperation(
                SyncLogCompanion.insert(
                  operationId: '00000000-0000-7000-8000-0000000000e6',
                  entityTableName: 'tasks',
                  recordId: taskId,
                  operation: 'update',
                  expectedServerVersion: const Value(5),
                  payload: jsonEncode(newerLocalPayload),
                  state: const Value('pending'),
                  createdAt: now.add(const Duration(minutes: 2)),
                  updatedAt: now.add(const Duration(minutes: 2)),
                ),
              );
            });
          }

          final sync = SyncRepository.withGateway(
            db,
            _FakeGateway(),
            'account',
          );
          if (keepRemote) {
            await sync.keepRemote(conflictId);
          } else {
            await sync.keepLocal(conflictId);
          }

          final task = (await TaskRepository(db).getTaskById(taskId))!;
          final selected = keepRemote ? remoteEvent : localEvent;
          expect(task.title, selected.newTitle);
          expect(task.displayPlanChangeId, selected.id);
          expect(
            task.planTitleHistory.map((event) => event.id),
            orderedEquals([
              localEvent.id,
              remoteEvent.id,
              if (keepRemote) newerLocalEvent.id,
            ]),
          );
          final pending = await db.syncDao.getActiveOperationsForRecord(
            'tasks',
            taskId,
          );
          expect(pending, hasLength(1));
          expect(pending.single.expectedServerVersion, 6);
          final queued = jsonDecode(pending.single.payload) as Map;
          expect(queued['title'], selected.newTitle);
          expect(queued['display_plan_change_id'], selected.id);
          expect(
            PlanTitleHistory.decodeJson(
              queued['plan_title_history_json'] as String,
            ).map((event) => event.id),
            orderedEquals([
              localEvent.id,
              remoteEvent.id,
              if (keepRemote) newerLocalEvent.id,
            ]),
          );
        } finally {
          await db.close();
        }
      }

      await verifyChoice(keepRemote: false);
      await verifyChoice(keepRemote: true);
    },
  );

  test(
    'identified F03 permanent operation retries with its original identity',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _FakeGateway();
      final now = DateTime.utc(2026, 9, 16, 13);
      const taskId = '00000000-0000-7000-8000-000000000141';
      const operationId = '00000000-0000-7000-8000-000000000142';
      const unrelatedOperation = '00000000-0000-7000-8000-000000000144';
      final event = PlanTitleChange(
        id: '00000000-0000-7000-8000-000000000143',
        previousTitle: 'Common title',
        newTitle: 'Local title',
        changedAt: now,
      );
      final payload = _taskPayload(
        id: taskId,
        title: 'Local title',
        history: [event],
        displayPlanChangeId: event.id,
        now: now,
      )..['_planner_payload_version'] = 2;
      try {
        await db.syncDao.runWithoutOutbound(() async {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: taskId,
                  title: 'Local title',
                  startTime: Value(now),
                  endTime: Value(now.add(const Duration(hours: 1))),
                  estimatedDurationMin: const Value(60),
                  planTitleHistoryJson: Value(
                    PlanTitleHistory.encodeJson([event]),
                  ),
                  displayPlanChangeId: Value(event.id),
                  createdAt: now,
                  updatedAt: now,
                  serverVersion: const Value(5),
                ),
              );
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: operationId,
              entityTableName: 'tasks',
              recordId: taskId,
              operation: 'update',
              expectedServerVersion: const Value(5),
              payload: jsonEncode(payload),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
          await db.syncDao.enqueueOperation(
            SyncLogCompanion.insert(
              operationId: unrelatedOperation,
              entityTableName: 'categories',
              recordId: 'unrelated-category',
              operation: 'insert',
              payload: jsonEncode({
                '_planner_payload_version': 2,
                'id': 'unrelated-category',
                'name': 'Unrelated',
                'color_hex': '#4285F4',
                'sort_order': 0,
                'is_focus': 0,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
                'deleted_at': null,
              }),
              state: const Value('pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        });
        await db.syncDao.markPermanentError(
          operationId,
          now: now,
          error: 'Existing plan title events cannot be removed or changed',
        );
        await db.syncDao.markPermanentError(
          unrelatedOperation,
          now: now,
          error: 'unrelated invalid payload',
        );
        gateway.responses.add({
          'status': 'conflict',
          'server_version': 0,
          'change_id': 0,
          'actual_server_version': 6,
          'remote_snapshot': _taskPayload(
            id: taskId,
            title: 'Common title',
            history: const [],
            displayPlanChangeId: null,
            now: now,
          ),
        });

        final failure = await SyncRepository.withGateway(
          db,
          gateway,
          'account',
        ).push();

        expect(failure, isNull);
        expect(gateway.appliedTables, ['tasks']);
        expect((await db.syncDao.getOperation(operationId))?.state, 'conflict');
        final unrelated = await db.syncDao.getOperation(unrelatedOperation);
        expect(unrelated?.state, 'error');
        expect(unrelated?.lastError, startsWith('Permanent sync error: '));
        final conflict = (await db.syncDao.watchConflicts().first).single;
        expect(conflict.operationId, operationId);
        expect(conflict.actualServerVersion, 6);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'permanent repair refuses unchanged payload and queues a changed snapshot',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final now = DateTime.utc(2026, 1, 1, 9);
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'repair-category',
                name: 'Original',
                colorHex: '#4285F4',
                createdAt: now,
                updatedAt: now,
              ),
            );
        final failed = (await db.syncDao.getRetryableOperations(now)).single;
        await db.syncDao.markPermanentError(
          failed.operationId,
          now: now,
          error: 'invalid payload',
        );
        final repository = SyncRepository.withGateway(
          db,
          _FakeGateway(),
          'account',
        );

        await expectLater(
          repository.repairPermanentOperation(failed.operationId),
          throwsA(isA<SyncRepairException>()),
        );

        await db.syncDao.runWithoutOutbound(() async {
          await (db.update(
            db.categories,
          )..where((row) => row.id.equals('repair-category'))).write(
            const CategoriesCompanion(
              name: Value('Repaired'),
              revision: Value(2),
              syncStatus: Value(1),
            ),
          );
        });
        await repository.repairPermanentOperation(failed.operationId);

        final active = await db.syncDao.getActiveOperationsForRecord(
          'categories',
          'repair-category',
        );
        expect(active, hasLength(1));
        expect(active.single.state, 'pending');
        expect(jsonDecode(active.single.payload)['name'], 'Repaired');
      } finally {
        await db.close();
      }
    },
  );
}

Map<String, dynamic> _categoryChange({
  required int changeId,
  required String id,
  required String name,
  required DateTime now,
  String? operationId,
}) => {
  'change_id': changeId,
  'operation_id': operationId ?? 'remote-operation-$changeId',
  'table_name': 'categories',
  'record_id': id,
  'operation': 'insert',
  'server_version': changeId,
  'server_timestamp': now.toIso8601String(),
  'payload': {
    'id': id,
    'name': name,
    'color_hex': '#4285F4',
    'sort_order': 0,
    'is_focus': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'deleted_at': null,
  },
};

Map<String, dynamic> _taskPayload({
  required String id,
  required String title,
  required List<PlanTitleChange> history,
  required String? displayPlanChangeId,
  required DateTime now,
  String? recurrenceRemovalReason,
}) => {
  'id': id,
  'title': title,
  'description': null,
  'start_time': now.toIso8601String(),
  'end_time': now.add(const Duration(hours: 1)).toIso8601String(),
  'estimated_duration_min': 60,
  'actual_duration_min': null,
  'manual_duration_adjustment_min': 0,
  'manual_actual_set': 0,
  'category_id': null,
  'priority': 0,
  'status': 'planned',
  'notes': null,
  'recurring_rule_id': null,
  'recurrence_removal_reason': recurrenceRemovalReason,
  'rescheduled_from_id': null,
  'rescheduled_to_id': null,
  'is_inbox': 0,
  'inbox_content_version': 0,
  'due_date': null,
  'missed_at': null,
  'plan_title_history_json': PlanTitleHistory.encodeJson(history),
  'display_plan_change_id': displayPlanChangeId,
  'created_at': now.toIso8601String(),
  'updated_at': now.toIso8601String(),
  'deleted_at': null,
};

Map<String, dynamic> _taskChange({
  required int changeId,
  required String operationId,
  required Map<String, dynamic> payload,
  required DateTime now,
}) => {
  'change_id': changeId,
  'operation_id': operationId,
  'table_name': 'tasks',
  'record_id': payload['id'],
  'operation': 'update',
  'server_version': changeId,
  'server_timestamp': now.toIso8601String(),
  'payload': payload,
};

Map<String, dynamic> _dayContextChange({
  required int changeId,
  required String date,
  required String kind,
  required DateTime now,
}) {
  final id = generateDeterministicUuid('day-context:$date');
  return {
    'change_id': changeId,
    'operation_id': 'remote-day-context-$changeId',
    'table_name': 'day_contexts',
    'record_id': id,
    'operation': 'insert',
    'server_version': changeId,
    'server_timestamp': now.toIso8601String(),
    'payload': {
      'id': id,
      'date': date,
      'kind': kind,
      'custom_label': kind == 'custom' ? 'Remote context' : null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
    },
  };
}

class _FakeGateway implements SyncRemoteGateway {
  final expectedVersions = <int?>[];
  final payloadVersions = <int>[];
  final payloads = <Map<String, dynamic>>[];
  Map<String, dynamic> capabilities = const {
    'protocol_version': 2,
    'payload_versions': [1, 2],
    'schedule_duration_projection': true,
    'inbox_content_version': true,
    'due_date': true,
    'plan_title_history': true,
    'manual_actual_source': true,
    'timer_state_machine': true,
    'day_contexts': true,
    'recurrence_removal_provenance': true,
  };
  final appliedTables = <String>[];
  final responses = <Object?>[];
  final pullPages = <List<Object?>>[];
  final pullCursors = <int>[];
  Object? applyError;
  void Function()? onApply;
  void Function()? onPull;

  @override
  Future<Object?> getCapabilities() async => capabilities;

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) async {
    onApply?.call();
    expectedVersions.add(expectedServerVersion);
    payloadVersions.add(payloadVersion);
    payloads.add(payload);
    appliedTables.add(tableName);
    if (applyError != null) throw applyError!;
    if (responses.isNotEmpty) return responses.removeAt(0);
    return {
      'status': 'applied',
      'server_version': 8,
      'change_id': 1,
      'server_timestamp': '2026-01-02T00:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    pullCursors.add(afterChangeId);
    onPull?.call();
    if (pullPages.isEmpty) return const <Object>[];
    final page = pullPages.removeAt(0);
    return page;
  }
}
