import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('day planning and overdue reschedule flow', (tester) async {
    final scope = await _mountApp(tester);
    final database = scope.read(appDatabaseProvider);
    final tasks = TaskRepository(database);
    final now = DateTime.now();
    final planned = await tasks.insertTask(
      Task(
        id: _uuid('101'),
        title: 'Integration planning task',
        startTime: startOfDay(now).add(const Duration(hours: 9)),
        endTime: startOfDay(now).add(const Duration(hours: 10)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Integration planning task'), findsWidgets);

    final overdue = await tasks.insertTask(
      Task(
        id: _uuid('102'),
        title: 'Integration overdue task',
        startTime: now.subtract(const Duration(days: 1, hours: 2)),
        endTime: now.subtract(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final inbox = InboxRepository(database);
    expect(await inbox.stampOverdue(now), 1);
    final successor = await inbox.rescheduleOverdue(
      overdue.id,
      startOfDay(now).add(const Duration(hours: 14)),
      startOfDay(now).add(const Duration(hours: 15)),
      successorId: _uuid('103'),
    );
    expect(
      (await tasks.getTaskById(overdue.id))!.status.dbValue,
      'rescheduled',
    );
    expect(successor.rescheduledFromId, overdue.id);
    expect(successor.title, overdue.title);
    expect((await tasks.getTaskById(planned.id))!.status.dbValue, 'planned');
    await _runTimerFlow();
    await _runBackupFlow();
    await _runSyncFlow();
  });
}

Future<void> _runTimerFlow() async {
  final database = await _newDatabase();
  addTearDown(() => database.close());
  final tasks = TaskRepository(database);
  final task = await tasks.insertTask(
    Task(
      id: _uuid('201'),
      title: 'Persisted timer task',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  var clock = DateTime.utc(2026, 9, 12, 9);
  final timer = TimerService(database, clock: () => clock);

  await timer.start(task.id);
  final first = (await database.select(database.timerSessions).get()).single;
  clock = first.startedAt.add(const Duration(seconds: 65));
  await timer.pauseAt(clock);
  clock = clock.add(const Duration(minutes: 30));
  await timer.resume(task.id);
  clock = clock.add(const Duration(seconds: 61));
  await timer.stopAt(clock);

  final sessions = await database.select(database.timerSessions).get();
  final persistedTask = await tasks.getTaskById(task.id);
  expect(sessions, hasLength(1));
  expect(sessions.single.endedAt, isNotNull);
  expect(sessions.single.state, 'finished');
  expect(sessions.single.durationSec, 126);
  expect(persistedTask!.actualDurationMin, 2);
}

Future<void> _runBackupFlow() async {
  final sourceDb = await _newDatabase();
  final targetDb = await _newDatabase();
  addTearDown(() async {
    await sourceDb.close();
    await targetDb.close();
  });
  final now = DateTime.utc(2026, 8, 29, 9);
  await sourceDb
      .into(sourceDb.categories)
      .insert(
        CategoriesCompanion.insert(
          id: _uuid('301'),
          name: 'Integration category',
          colorHex: '#4285F4',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await sourceDb
      .into(sourceDb.tasks)
      .insert(
        TasksCompanion.insert(
          id: _uuid('302'),
          title: 'Backup task',
          categoryId: Value(_uuid('301')),
          createdAt: now,
          updatedAt: now,
        ),
      );
  final service = BackupService(sourceDb);
  final source = await service.exportJson();
  await BackupService(targetDb).importJson(source, ownershipConfirmed: true);
  expect(await targetDb.taskDao.getTaskById(_uuid('302')), isNotNull);

  final document = jsonDecode(source) as Map<String, dynamic>;
  final content = document['content'] as Map<String, dynamic>;
  final data = content['data'] as Map<String, dynamic>;
  (data['tasks'] as List).first['title'] = 'tampered';
  final rejectedTarget = await _newDatabase();
  addTearDown(rejectedTarget.close);
  await expectLater(
    BackupService(rejectedTarget)
        .importJson(jsonEncode(document), ownershipConfirmed: true),
    throwsA(isA<BackupValidationException>()),
  );

  final conflictTarget = await _newDatabase();
  addTearDown(conflictTarget.close);
  await conflictTarget
      .into(conflictTarget.categories)
      .insert(
        CategoriesCompanion.insert(
          id: _uuid('301'),
          name: 'Local category',
          colorHex: '#4285F4',
          createdAt: now,
          updatedAt: now,
        ),
      );
  final conflict = await BackupService(conflictTarget)
      .importJson(source, ownershipConfirmed: true);
  expect(
    conflict.conflicts.any((item) => item.table == 'tasks' && item.isBlocked),
    isTrue,
  );
  expect(await conflictTarget.taskDao.getTaskById(_uuid('302')), isNull);

  final rollbackTarget = await _newDatabase();
  addTearDown(rollbackTarget.close);
  await rollbackTarget
      .into(rollbackTarget.dailyReviews)
      .insert(
        DailyReviewsCompanion.insert(
          id: _uuid('303'),
          date: '2026-08-29',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await expectLater(
    BackupService(rollbackTarget).importJson(
      await _backupWithReview(sourceDb, now),
      ownershipConfirmed: true,
    ),
    throwsA(anything),
  );
  expect(await rollbackTarget.select(rollbackTarget.categories).get(), isEmpty);
}

Future<void> _runSyncFlow() async {
  final first = await _newDatabase();
  final second = await _newDatabase();
  addTearDown(() async {
    await first.close();
    await second.close();
  });
  final gateway = _DeterministicGateway();
  final firstSync = SyncRepository.withGateway(first, gateway, 'account');
  final secondSync = SyncRepository.withGateway(second, gateway, 'account');
  final category = await CategoryRepository(first).insertCategory(
    Category(
      id: _uuid('401'),
      name: 'Synced category',
      colorHex: '#4285F4',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  final task = await TaskRepository(first).insertTask(
    Task(
      id: _uuid('402'),
      title: 'Synced task',
      categoryId: category.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  await firstSync.sync();
  await secondSync.pull();
  expect(await second.taskDao.getTaskById(task.id), isNotNull);

  final firstTask = (await first.taskDao.getTaskById(task.id))!;
  await first.taskDao.updateTask(firstTask.copyWith(title: 'First client'));
  await firstSync.push();
  final secondTask = (await second.taskDao.getTaskById(task.id))!;
  await second.taskDao.updateTask(secondTask.copyWith(title: 'Second client'));
  await secondSync.push();

  expect(await second.syncDao.watchConflicts().first, hasLength(1));
  expect((await first.taskDao.getTaskById(task.id))!.title, 'First client');
}

Future<AppDatabase> _newDatabase() async =>
    AppDatabase(NativeDatabase.memory());

Future<ProviderContainer> _mountApp(WidgetTester tester) async {
  final database = await _newDatabase();
  await CategoryRepository(database).seedDefaultsIfEmpty();
  await database.syncDao.setSetting('onboarding.completed', 'true');
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PersonalPlannerApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await database.close();
    });
  });
  return container;
}

Future<String> _backupWithReview(AppDatabase database, DateTime now) async {
  await database
      .into(database.dailyReviews)
      .insert(
        DailyReviewsCompanion.insert(
          id: _uuid('304'),
          date: '2026-08-29',
          createdAt: now,
          updatedAt: now,
        ),
      );
  return BackupService(database).exportJson();
}

String _uuid(String suffix) =>
    '00000000-0000-7000-8000-${suffix.padLeft(12, '0')}';

class _DeterministicGateway implements SyncRemoteGateway {
  final _versions = <String, int>{};
  final _snapshots = <String, Map<String, dynamic>>{};
  final _changes = <Map<String, dynamic>>[];
  var _changeId = 0;

  @override
  Future<Object?> getCapabilities() async => const {
    'protocol_version': 2,
    'payload_versions': [1, 2],
    'schedule_duration_projection': true,
    'inbox_content_version': true,
    'due_date': true,
    'plan_title_history': true,
    'manual_actual_source': true,
    'timer_state_machine': true,
    'day_contexts': true,
  };

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
  }) async {
    final key = '$tableName\u0000$recordId';
    final currentVersion = _versions[key];
    if (currentVersion != null && expectedServerVersion != currentVersion) {
      return {
        'status': 'conflict',
        'server_version': currentVersion,
        'actual_server_version': currentVersion,
        'change_id': _changeId,
        'server_timestamp': DateTime.now().toUtc().toIso8601String(),
        'remote_snapshot': _snapshots[key],
      };
    }
    final nextVersion = (currentVersion ?? 0) + 1;
    _versions[key] = nextVersion;
    _snapshots[key] = Map<String, dynamic>.from(payload);
    _changeId++;
    _changes.add({
      'change_id': _changeId,
      'operation_id': operationId,
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'server_version': nextVersion,
      'server_timestamp': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });
    return {
      'status': 'applied',
      'server_version': nextVersion,
      'change_id': _changeId,
      'server_timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    return _changes
        .where((change) => (change['change_id'] as int) > afterChangeId)
        .take(limit)
        .toList();
  }
}
