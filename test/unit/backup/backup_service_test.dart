import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/settings/data/backup_codec.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    setupSqliteForTests();
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'exports every user table, tombstones, settings, and checksum',
    () async {
      await _seedDatabase(database);

      final json = await BackupService(database).exportJson();
      final document = jsonDecode(json) as Map<String, dynamic>;
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;

      expect(document['format'], 'personal_planner_backup');
      expect(document['schema_version'], plannerBackupSchemaVersion);
      expect(document['content_checksum'], isA<String>());
      expect(
        data.keys,
        containsAll(<String>[
          'tasks',
          'subtasks',
          'categories',
          'tags',
          'task_tags',
          'recurring_rules',
          'task_templates',
          'daily_reviews',
          'weekly_reviews',
          'timer_sessions',
          'settings',
        ]),
      );
      expect((data['tasks'] as List).length, 2);
      expect((data['settings'] as Map)['theme_mode'], 'dark');
      expect(
        (data['tasks'] as List).any(
          (row) => (row as Map)['deleted_at'] != null,
        ),
        isTrue,
      );
      expect((data['tasks'] as List).first, isNot(contains('server_version')));
      expect(
        (data['settings'] as Map).keys,
        isNot(contains('sync.apply_mode')),
      );
    },
  );

  test(
    'imports valid data atomically and creates a fresh local mutation set',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);

      final result = await BackupService(restored)
          .importJson(source, ownershipConfirmed: true);

      expect(result.inserted, 12);
      expect(result.skipped, 0);
      expect(result.conflicts, isEmpty);
      expect(await restored.select(restored.tasks).get(), hasLength(2));
      expect(await restored.select(restored.subtasks).get(), hasLength(1));
      expect(await restored.select(restored.taskTags).get(), hasLength(1));
      expect(await restored.select(restored.timerSessions).get(), hasLength(1));
      expect(await restored.syncDao.pendingCount(), greaterThanOrEqualTo(10));
    },
  );

  test(
    'backup round trips structured plan history and rejects corrupt events',
    () async {
      final first = PlanTitleChange(
        id: '00000000-0000-7000-8000-0000000000f1',
        previousTitle: 'Read book',
        newTitle: 'Draft proposal',
        changedAt: _time.subtract(const Duration(hours: 1)),
        revertedAt: _time,
      );
      final selected = PlanTitleChange(
        id: '00000000-0000-7000-8000-0000000000f2',
        previousTitle: 'Draft proposal',
        newTitle: 'Office work',
        changedAt: _time.add(const Duration(hours: 1)),
      );
      final task = await TaskRepository(database).insertTask(
        Task(
          id: '00000000-0000-7000-8000-0000000000f3',
          title: 'Office work',
          startTime: _time,
          endTime: _time.add(const Duration(hours: 1)),
          planTitleHistory: [first, selected],
          displayPlanChangeId: selected.id,
          createdAt: _time,
          updatedAt: _time,
        ),
      );

      final source = await BackupService(database).exportJson();
      final document = jsonDecode(source) as Map<String, dynamic>;
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      final exported = (data['tasks'] as List).cast<Map>().singleWhere(
        (row) => row['id'] == task.id,
      );
      expect(exported['plan_title_history'], isA<List>());
      expect((exported['plan_title_history'] as List), hasLength(2));
      expect(exported, isNot(contains('plan_title_history_json')));
      expect(exported['display_plan_change_id'], selected.id);

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await BackupService(restored)
          .importJson(source, ownershipConfirmed: true);
      final restoredTask = (await TaskRepository(restored)
          .getTaskById(task.id))!;
      expect(restoredTask.displayPlanChangeId, selected.id);
      expect(restoredTask.planTitleHistory, hasLength(2));
      expect(restoredTask.planTitleHistory.first.revertedAt, _time);
      expect(restoredTask.planTitleHistory.last.id, selected.id);

      final corrupt = jsonDecode(source) as Map<String, dynamic>;
      final corruptContent = corrupt['content'] as Map<String, dynamic>;
      final corruptData = corruptContent['data'] as Map<String, dynamic>;
      final corruptTask = (corruptData['tasks'] as List)
          .cast<Map>()
          .singleWhere((row) => row['id'] == task.id);
      corruptTask['plan_title_history'] = [
        {
          'id': selected.id,
          'previous_title': 'Read book',
          'new_title': 'Office work',
          'changed_at': 'not-a-date',
          'reverted_at': null,
        },
      ];
      corrupt['content_checksum'] = BackupCodec.checksum(corruptContent);
      final rejected = AppDatabase(NativeDatabase.memory());
      addTearDown(rejected.close);
      expect(
        BackupService(rejected)
            .importJson(jsonEncode(corrupt), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await rejected.select(rejected.tasks).get(), isEmpty);
    },
  );

  test('backup round trip preserves the canonical missed marker', () async {
    final task = await TaskRepository(database).insertTask(
      Task(
        id: '00000000-0000-7000-8000-0000000000f4',
        title: 'Missed backup',
        missedAt: '2026-09-14T18:30',
        createdAt: _time,
        updatedAt: _time,
      ),
    );
    final source = await BackupService(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    await BackupService(restored).importJson(source, ownershipConfirmed: true);
    expect(
      (await TaskRepository(restored).getTaskById(task.id))?.missedAt,
      '2026-09-14T18:30',
    );
    final exportedAgain = await BackupService(restored).exportJson();
    final data =
        ((jsonDecode(exportedAgain) as Map<String, dynamic>)['content']
                as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final row = (data['tasks'] as List).cast<Map>().singleWhere(
      (value) => value['id'] == task.id,
    );
    expect(row['missed_at'], '2026-09-14T18:30');
  });

  test(
    'export freezes unfinished running work as portable paused data',
    () async {
      await _seedDatabase(database);
      final now = DateTime.now().toUtc();
      final started = now.subtract(const Duration(minutes: 2));
      final closedAt = now.subtract(const Duration(minutes: 1));
      await database
          .into(database.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: '33333333-3333-4333-8333-333333333333',
              taskId: _taskId,
              startedAt: started,
              durationSec: const Value(60),
              state: const Value('running'),
              runningSince: Value(closedAt),
              workIntervalsJson: Value(
                jsonEncode([
                  {
                    'start_at': started.toIso8601String(),
                    'end_at': closedAt.toIso8601String(),
                    'duration_sec': 60,
                  },
                ]),
              ),
              ownerDeviceId: const Value(
                '11111111-1111-4111-8111-111111111111',
              ),
              createdAt: started,
              updatedAt: now,
            ),
          );

      final document = jsonDecode(
        await BackupService(database).exportJson(),
      ) as Map<String, dynamic>;
      final data =
          (document['content'] as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final exported = (data['timer_sessions'] as List).cast<Map>().singleWhere(
        (row) => row['id'] == '33333333-3333-4333-8333-333333333333',
      );
      expect(exported['state'], 'paused');
      expect(exported['running_since'], isNull);
      expect(exported['owner_device_id'], isNull);
      expect(exported['duration_sec'], greaterThanOrEqualTo(60));
      final intervals = exported['work_intervals'] as List;
      expect((intervals.first as Map)['start_at'], isA<String>());
      expect((intervals.first as Map)['start_at'], endsWith('Z'));

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true);
      final imported = await restored.timerDao.getSessionById(
        '33333333-3333-4333-8333-333333333333',
      );
      expect(imported?.state, 'paused');
      expect(imported?.ownerDeviceId, isNull);
      expect(imported?.runningSince, isNull);
    },
  );

  test(
    'backup round trips a tombstoned day context without task data',
    () async {
      await _seedDatabase(database);
      final context = await DayContextRepository(database)
          .save('2026-08-31', DayContextKind.travel, null);
      await DayContextRepository(database).remove(context.id);

      final source = await BackupService(database).exportJson();
      final document = jsonDecode(source) as Map<String, dynamic>;
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      expect(data['day_contexts'], hasLength(1));
      expect((data['day_contexts'] as List).single['kind'], 'travel');
      expect((data['day_contexts'] as List).single['deleted_at'], isNotNull);

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await BackupService(restored)
          .importJson(source, ownershipConfirmed: true);

      final rows = await restored.select(restored.dayContexts).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, context.id);
      expect(rows.single.date, '2026-08-31');
      expect(rows.single.kind, 'travel');
      expect(rows.single.deletedAt, isNotNull);
      expect(await restored.select(restored.tasks).get(), hasLength(2));
    },
  );

  test(
    'v1 import adapts stale task estimates after checksum verification',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final document = jsonDecode(source) as Map<String, dynamic>;
      _convertEnvelopeToV1(document);
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      (data['tasks'] as List).first['estimated_duration_min'] = 16;
      document['content_checksum'] = BackupCodec.checksum(content);

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true);

      final task = (await restored.select(restored.tasks).get()).first;
      expect(task.estimatedDurationMin, 60);
    },
  );

  test(
    'v1 import adapts legacy Inbox content once and defaults due date',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final document = jsonDecode(source) as Map<String, dynamic>;
      _convertEnvelopeToV1(document);
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      final task = Map<String, dynamic>.from(
        (data['tasks'] as List).first as Map<String, dynamic>,
      );
      task['title'] = 'Legacy title';
      task['description'] = 'Legacy notes';
      task['is_inbox'] = true;
      task['start_time'] = null;
      task['end_time'] = null;
      (data['tasks'] as List)[0] = task;
      document['content_checksum'] = BackupCodec.checksum(content);

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true);
      final imported = (await restored.select(restored.tasks).get()).first;
      expect(imported.description, 'Legacy title\n\nLegacy notes');
      expect(imported.inboxContentVersion, 1);
      expect(imported.dueDate, isNull);
    },
  );

  test('pre-R3 v1 backups import with no day contexts', () async {
    await _seedDatabase(database);
    final document = jsonDecode(
      await BackupService(database).exportJson(),
    ) as Map<String, dynamic>;
    _convertEnvelopeToV1(document);

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await BackupService(restored)
        .importJson(jsonEncode(document), ownershipConfirmed: true);
    expect(await restored.select(restored.dayContexts).get(), isEmpty);
  });

  test('bad v1 checksum is rejected before compatibility conversion', () async {
    await _seedDatabase(database);
    final document = jsonDecode(
      await BackupService(database).exportJson(),
    ) as Map<String, dynamic>;
    _convertEnvelopeToV1(document);
    final content = document['content'] as Map<String, dynamic>;
    final data = content['data'] as Map<String, dynamic>;
    (data['tasks'] as List).first['title'] = 'Tampered legacy title';
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    expect(
      BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true),
      throwsA(
        isA<BackupValidationException>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
    expect(await restored.select(restored.tasks).get(), isEmpty);
  });

  test('v1 keys are validated before compatibility fields are added', () async {
    await _seedDatabase(database);
    final document = jsonDecode(
      await BackupService(database).exportJson(),
    ) as Map<String, dynamic>;
    _convertEnvelopeToV1(document);
    final content = document['content'] as Map<String, dynamic>;
    final data = content['data'] as Map<String, dynamic>;
    (data['tasks'] as List).first['due_date'] = null;
    document['content_checksum'] = BackupCodec.checksum(content);
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    expect(
      BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true),
      throwsA(
        isA<BackupValidationException>().having(
          (error) => error.message,
          'message',
          contains('unsupported or missing fields'),
        ),
      ),
    );
    expect(await restored.select(restored.tasks).get(), isEmpty);
  });

  test('future backup versions are rejected before writes', () async {
    await _seedDatabase(database);
    final document = jsonDecode(
      await BackupService(database).exportJson(),
    ) as Map<String, dynamic>;
    final content = document['content'] as Map<String, dynamic>;
    document['schema_version'] = 3;
    content['schema_version'] = 3;
    document['content_checksum'] = BackupCodec.checksum(content);
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);

    expect(
      BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await restored.select(restored.tasks).get(), isEmpty);
  });

  test(
    'legacy unfinished timers import paused without wall-clock growth',
    () async {
      await _seedDatabase(database);
      final document = jsonDecode(
        await BackupService(database).exportJson(),
      ) as Map<String, dynamic>;
      _convertEnvelopeToV1(document);
      final content = document['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      final timer = (data['timer_sessions'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['id'] == _timerId);
      timer['started_at'] = DateTime.utc(2000).toIso8601String();
      timer['ended_at'] = null;
      timer['duration_sec'] = 120;
      document['content_checksum'] = BackupCodec.checksum(content);
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);

      await BackupService(restored)
          .importJson(jsonEncode(document), ownershipConfirmed: true);

      final imported = await restored.timerDao.getSessionById(_timerId);
      expect(imported?.state, 'paused');
      expect(imported?.durationSec, 120);
      expect(imported?.runningSince, isNull);
      expect(imported?.ownerDeviceId, isNull);
    },
  );

  test('backup rejects malformed due dates before any write', () async {
    await _seedDatabase(database);
    final source = await BackupService(database).exportJson();
    final document = jsonDecode(source) as Map<String, dynamic>;
    final content = document['content'] as Map<String, dynamic>;
    final data = content['data'] as Map<String, dynamic>;
    final tasks = [
      for (final raw in data['tasks'] as List)
        Map<String, dynamic>.from(raw as Map<String, dynamic>),
    ];
    tasks.first['due_date'] = '2026-02-30';
    data['tasks'] = tasks;
    document['content_checksum'] = BackupCodec.checksum(content);
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);

    expect(
      BackupService(target)
          .importJson(jsonEncode(document), ownershipConfirmed: true),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await target.select(target.tasks).get(), isEmpty);
  });

  test('rejects checksum changes before touching the database', () async {
    await _seedDatabase(database);
    final source = await BackupService(database).exportJson();
    final document = jsonDecode(source) as Map<String, dynamic>;
    final content = document['content'] as Map<String, dynamic>;
    final data = content['data'] as Map<String, dynamic>;
    (data['tasks'] as List).first['title'] = 'tampered';
    final tampered = jsonEncode(document);
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);

    expect(
      () =>
          BackupService(target).importJson(tampered, ownershipConfirmed: true),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await target.select(target.tasks).get(), isEmpty);
  });

  test(
    'merge preserves differing IDs as conflicts without overwriting',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await target
          .into(target.categories)
          .insert(
            CategoriesCompanion.insert(
              id: _categoryId,
              name: 'Local name',
              colorHex: '#4285F4',
              createdAt: _time,
              updatedAt: _time,
            ),
          );

      final result = await BackupService(target)
          .importJson(source, ownershipConfirmed: true);

      expect(result.conflicts.map((item) => item.id), contains(_categoryId));
      expect(
        (await target.categoryDao.getCategoryById(_categoryId))!.name,
        'Local name',
      );
    },
  );

  test('merge does not overwrite portable settings', () async {
    await _seedDatabase(database);
    final source = await BackupService(database).exportJson();
    await database.syncDao.setSetting('theme_mode', 'light');

    final result = await BackupService(database)
        .importJson(source, ownershipConfirmed: true);

    expect(
      result.conflicts,
      contains(
        isA<BackupConflict>().having(
          (conflict) => conflict.table,
          'table',
          'settings',
        ),
      ),
    );
    final row = await (database.select(
      database.appSettings,
    )..where((setting) => setting.key.equals('theme_mode'))).getSingle();
    expect(row.value, 'light');
  });

  test('conflicting parents block their dependent closure', () async {
    await _seedDatabase(database);
    final source = await BackupService(database).exportJson();
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    await target
        .into(target.categories)
        .insert(
          CategoriesCompanion.insert(
            id: _categoryId,
            name: 'Local category',
            colorHex: '#4285F4',
            createdAt: _time,
            updatedAt: _time,
          ),
        );

    final result = await BackupService(target)
        .importJson(source, ownershipConfirmed: true);

    expect(
      result.conflicts,
      contains(
        isA<BackupConflict>()
            .having((conflict) => conflict.table, 'table', 'recurring_rules')
            .having(
              (conflict) => conflict.kind,
              'kind',
              BackupConflictKind.blocked,
            ),
      ),
    );
    expect(
      result.conflicts,
      contains(
        isA<BackupConflict>()
            .having((conflict) => conflict.table, 'table', 'subtasks')
            .having(
              (conflict) => conflict.kind,
              'kind',
              BackupConflictKind.blocked,
            ),
      ),
    );
    expect(await target.taskDao.getTaskById(_taskId), isNull);
    expect(await target.recurringRuleDao.getRuleById(_ruleId), isNull);
    expect(
      (await target.categoryDao.getCategoryById(_categoryId))!.name,
      'Local category',
    );
  });

  test('a late database failure rolls back the complete merge', () async {
    await _seedDatabase(database);
    final source = await BackupService(database).exportJson();
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    final localTask = await TaskRepository(target).insertTask(
      Task(
        id: '',
        title: 'Pre-import task',
        startTime: DateTime.utc(2026, 8, 29, 8),
        endTime: DateTime.utc(2026, 8, 29, 9),
        createdAt: _time,
        updatedAt: _time,
      ),
    );
    await target.syncDao.setSetting('theme_mode', 'light');
    await target
        .into(target.dailyReviews)
        .insert(
          DailyReviewsCompanion.insert(
            id: _otherReviewId,
            date: '2026-08-29',
            createdAt: _time,
            updatedAt: _time,
          ),
        );
    final pendingBefore = await target.syncDao.pendingCount();
    final ftsBefore = await target
        .customSelect('SELECT title FROM tasks_fts ORDER BY rowid')
        .get();

    await expectLater(
      BackupService(target).importJson(source, ownershipConfirmed: true),
      throwsA(anything),
    );
    expect(await target.select(target.categories).get(), isEmpty);
    expect(await target.select(target.tags).get(), isEmpty);
    expect(await target.taskDao.getTaskById(localTask.id), isNotNull);
    expect(await target.syncDao.pendingCount(), pendingBefore);
    final ftsAfter = await target
        .customSelect('SELECT title FROM tasks_fts ORDER BY rowid')
        .get();
    expect(
      ftsAfter.map((row) => row.data['title']).toList(),
      ftsBefore.map((row) => row.data['title']).toList(),
    );
    final theme = await (target.select(
      target.appSettings,
    )..where((row) => row.key.equals('theme_mode'))).getSingle();
    expect(theme.value, 'light');
    final review = await (target.select(
      target.dailyReviews,
    )..where((row) => row.id.equals(_otherReviewId))).getSingle();
    expect(review.date, '2026-08-29');
  });

  test(
    'rejects unsupported fields and oversized documents before writes',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final document = jsonDecode(source) as Map<String, dynamic>;
      document['unexpected'] = true;
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      expect(
        BackupService(target)
            .importJson(jsonEncode(document), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await target.select(target.tasks).get(), isEmpty);
      expect(
        () => BackupService(target).importJson(
          'x' * (plannerBackupMaxBytes + 1),
          ownershipConfirmed: true,
        ),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );

  test(
    'rejects invalid metadata, settings, duplicate IDs, and references',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final envelope = jsonDecode(source) as Map<String, dynamic>;
      final content = envelope['content'] as Map<String, dynamic>;
      final data = content['data'] as Map<String, dynamic>;
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      final badCounts = jsonDecode(source) as Map<String, dynamic>;
      (badCounts['validation'] as Map<String, dynamic>)['record_counts'] = {
        ...((badCounts['validation'] as Map<String, dynamic>)['record_counts']
            as Map<String, dynamic>),
        'tasks': 999,
      };
      expect(
        BackupService(target)
            .importJson(jsonEncode(badCounts), ownershipConfirmed: true),
        throwsA(isA<BackupValidationException>()),
      );

      final invalidSettings = Map<String, dynamic>.from(data);
      invalidSettings['settings'] = {
        ...(data['settings'] as Map<String, dynamic>),
        'theme_mode': 'neon',
      };
      expect(
        BackupService(target).importJson(
          BackupCodec.encodeData(invalidSettings),
          ownershipConfirmed: true,
        ),
        throwsA(isA<BackupValidationException>()),
      );

      final duplicate = Map<String, dynamic>.from(data);
      duplicate['categories'] = [
        ...(data['categories'] as List<dynamic>),
        (data['categories'] as List<dynamic>).first,
      ];
      expect(
        BackupService(target).importJson(
          BackupCodec.encodeData(duplicate),
          ownershipConfirmed: true,
        ),
        throwsA(isA<BackupValidationException>()),
      );

      final missingReference = Map<String, dynamic>.from(data);
      final tasks = [
        for (final row in data['tasks'] as List<dynamic>)
          Map<String, dynamic>.from(row as Map<String, dynamic>),
      ];
      tasks.first['category_id'] = _otherCategoryId;
      missingReference['tasks'] = tasks;
      expect(
        BackupService(target).importJson(
          BackupCodec.encodeData(missingReference),
          ownershipConfirmed: true,
        ),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await target.select(target.tasks).get(), isEmpty);
    },
  );

  test(
    'replace requires confirmation and restores after validating backup',
    () async {
      await _seedDatabase(database);
      final source = await BackupService(database).exportJson();
      final old = AppDatabase(NativeDatabase.memory());
      addTearDown(old.close);
      await old
          .into(old.categories)
          .insert(
            CategoriesCompanion.insert(
              id: _otherCategoryId,
              name: 'Old data',
              colorHex: '#34A853',
              createdAt: _time,
              updatedAt: _time,
            ),
          );
      final preImport = await BackupService(old).exportJson();

      await BackupService(old).replaceFromJson(
        source,
        preImportBackup: preImport,
        confirmed: true,
        ownershipConfirmed: true,
      );

      expect(await old.categoryDao.getCategoryById(_categoryId), isNotNull);
      expect(await old.categoryDao.getCategoryById(_otherCategoryId), isNull);
    },
  );

  test('replacement cannot resurrect obsolete sync metadata', () async {
    final incoming = AppDatabase(NativeDatabase.memory());
    addTearDown(incoming.close);
    final source = await BackupService(incoming).exportJson();
    final preImport = await BackupService(database).exportJson();
    try {
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: _otherCategoryId,
              name: 'Queued before replacement',
              colorHex: '#34A853',
              createdAt: _time,
              updatedAt: _time,
            ),
          );
      expect(await database.syncDao.pendingCount(), 1);
      await BackupService(database).replaceFromJson(
        source,
        preImportBackup: preImport,
        confirmed: true,
        ownershipConfirmed: true,
      );

      expect(await database.select(database.categories).get(), isEmpty);
      expect(await database.select(database.syncLog).get(), isEmpty);
      expect(await database.select(database.syncConflicts).get(), isEmpty);
      expect(await database.select(database.syncState).get(), isEmpty);
    } finally {
      // The test-level tearDown closes database; this block documents that the
      // incoming fixture is intentionally isolated from it.
    }
  });

  test(
    'replacement is refused once a database has synchronized account state',
    () async {
      final source = await BackupService(database).exportJson();
      final incoming = AppDatabase(NativeDatabase.memory());
      addTearDown(incoming.close);
      final replacement = await BackupService(incoming).exportJson();
      await database.syncDao.advanceCursor(
        'account-a',
        12,
        DateTime.utc(2026, 8, 30),
      );

      expect(
        () => BackupService(database).replaceFromJson(
          replacement,
          preImportBackup: source,
          confirmed: true,
          ownershipConfirmed: true,
        ),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );
}

void _convertEnvelopeToV1(Map<String, dynamic> document) {
  final content = document['content'] as Map<String, dynamic>;
  final data = content['data'] as Map<String, dynamic>;
  data.remove('day_contexts');
  for (final raw in data['tasks'] as List) {
    final row = raw as Map<String, dynamic>;
    row.remove('manual_actual_set');
    row.remove('inbox_content_version');
    row.remove('due_date');
    row.remove('plan_title_history');
    row.remove('display_plan_change_id');
  }
  for (final raw in data['timer_sessions'] as List) {
    final row = raw as Map<String, dynamic>;
    row.remove('state');
    row.remove('running_since');
    row.remove('work_intervals');
    row.remove('owner_device_id');
  }
  document['schema_version'] = 1;
  content['schema_version'] = 1;
  (document['validation'] as Map<String, dynamic>)['record_counts'] =
      BackupCodec.recordCounts(data);
  document['content_checksum'] = BackupCodec.checksum(content);
}

const _categoryId = '00000000-0000-7000-8000-000000000001';
const _otherCategoryId = '00000000-0000-7000-8000-000000000099';
const _tagId = '00000000-0000-7000-8000-000000000002';
const _ruleId = '00000000-0000-7000-8000-000000000003';
const _taskId = '00000000-0000-7000-8000-000000000004';
const _deletedTaskId = '00000000-0000-7000-8000-000000000005';
const _templateId = '00000000-0000-7000-8000-000000000006';
const _reviewId = '00000000-0000-7000-8000-000000000007';
const _weeklyId = '00000000-0000-7000-8000-000000000008';
const _subtaskId = '00000000-0000-7000-8000-000000000009';
const _timerId = '00000000-0000-7000-8000-00000000000a';
const _otherReviewId = '00000000-0000-7000-8000-00000000000b';
final _time = DateTime.utc(2026, 8, 29, 10);

Future<void> _seedDatabase(AppDatabase db) async {
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: _categoryId,
          name: 'Work',
          colorHex: '#4285F4',
          isFocus: const Value(true),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.tags)
      .insert(
        TagsCompanion.insert(
          id: _tagId,
          name: 'deep-work',
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.recurringRules)
      .insert(
        RecurringRulesCompanion.insert(
          id: _ruleId,
          rrule: 'FREQ=DAILY',
          taskTitle: 'Recurring',
          durationMin: 30,
          categoryId: Value(_categoryId),
          tagsJson: const Value('["00000000-0000-7000-8000-000000000002"]'),
          startTimeOfDay: '09:00',
          startDate: '2026-08-29',
          exceptionsJson: const Value('[]'),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: _taskId,
          title: 'Overnight task',
          startTime: Value(DateTime.utc(2026, 8, 29, 23, 30)),
          endTime: Value(DateTime.utc(2026, 8, 30, 0, 30)),
          estimatedDurationMin: const Value(60),
          actualDurationMin: const Value(10),
          manualDurationAdjustmentMin: const Value(10),
          categoryId: const Value(_categoryId),
          recurringRuleId: const Value(_ruleId),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: _deletedTaskId,
          title: 'Deleted history',
          createdAt: _time,
          updatedAt: _time,
          deletedAt: Value(_time.add(const Duration(minutes: 1))),
        ),
      );
  await db
      .into(db.taskTemplates)
      .insert(
        TaskTemplatesCompanion.insert(
          id: _templateId,
          name: 'Template',
          durationMin: 45,
          categoryId: const Value(_categoryId),
          tagsJson: const Value('["00000000-0000-7000-8000-000000000002"]'),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.dailyReviews)
      .insert(
        DailyReviewsCompanion.insert(
          id: _reviewId,
          date: '2026-08-29',
          energyLevel: const Value(4),
          winsJson: const Value('["Finished"]'),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.weeklyReviews)
      .insert(
        WeeklyReviewsCompanion.insert(
          id: _weeklyId,
          weekStartDate: '2026-08-24',
          overallRating: const Value(5),
          goalsMetJson: const Value('["Ship"]'),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.subtasks)
      .insert(
        SubtasksCompanion.insert(
          id: _subtaskId,
          taskId: _taskId,
          title: 'Check details',
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.taskTags)
      .insert(
        TaskTagsCompanion.insert(
          taskId: _taskId,
          tagId: _tagId,
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db
      .into(db.timerSessions)
      .insert(
        TimerSessionsCompanion.insert(
          id: _timerId,
          taskId: _taskId,
          startedAt: DateTime.utc(2026, 8, 29, 23, 35),
          endedAt: Value(DateTime.utc(2026, 8, 30, 0, 5)),
          durationSec: const Value(1800),
          state: const Value('finished'),
          createdAt: _time,
          updatedAt: _time,
        ),
      );
  await db.syncDao.setSetting('theme_mode', 'dark');
  await db.syncDao.setSetting('sync.enabled', 'true');
}
