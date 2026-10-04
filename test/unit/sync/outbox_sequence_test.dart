import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';
import 'package:sqlite3/open.dart';

import '../../helpers/sqlite_setup.dart';

/// Runs in the background connection's isolate, which does not share the
/// test isolate's `open.overrideFor` registration.
void _openSqlite() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}

void main() {
  setupSqliteForTests();

  late Directory directory;
  late AppDatabase db;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('planner_outbox_sequence');
    db = AppDatabase(
      NativeDatabase.createInBackground(
        File('${directory.path}/planner.sqlite3'),
        setup: AppDatabase.configureConnection,
        isolateSetup: _openSqlite,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  Map<String, Object?> payloadOf(SyncLogRow row) =>
      (jsonDecode(row.payload) as Map).cast<String, Object?>();

  Future<List<SyncLogRow>> retryable() => db.syncDao.getRetryableOperations(
    DateTime.now().toUtc().add(const Duration(days: 1)),
    limit: 1 << 20,
  );

  group('outbox sequence (DB-001)', () {
    test('timer stop pause and finish are pushed in creation order on a '
        'file-backed connection', () async {
      const iterations = 200;
      final tasks = TaskRepository(db);
      final timer = TimerService(db);
      final sessionIds = <String>[];
      for (var i = 0; i < iterations; i++) {
        final now = DateTime.now();
        final task = await tasks.insertTask(
          Task(id: '', title: 'Timer $i', createdAt: now, updatedAt: now),
        );
        final started = await timer.start(task.id);
        sessionIds.add(started.session!.id);
        final stopped = await timer.stop();
        expect(stopped.didFinish, isTrue);
      }

      final operations = await retryable();
      final position = {
        for (var i = 0; i < operations.length; i++)
          operations[i].operationId: i,
      };
      var sequenceInversions = 0;
      var pushInversions = 0;
      for (final sessionId in sessionIds) {
        final sessionOps = operations
            .where(
              (row) =>
                  row.entityTableName == 'timer_sessions' &&
                  row.recordId == sessionId,
            )
            .toList();
        final paused = sessionOps.singleWhere(
          (row) => payloadOf(row)['state'] == 'paused',
        );
        final finished = sessionOps.singleWhere(
          (row) => payloadOf(row)['state'] == 'finished',
        );
        expect(paused.seq, isNotNull);
        expect(finished.seq, isNotNull);
        if (paused.seq! >= finished.seq!) sequenceInversions++;
        if (position[paused.operationId]! >= position[finished.operationId]!) {
          pushInversions++;
        }
      }
      // ignore: avoid_print
      print(
        'TIMER pairs=${sessionIds.length} '
        'seqInverted=$sequenceInversions pushInverted=$pushInversions',
      );
      expect(sequenceInversions, 0);
      expect(pushInversions, 0);
    });

    test(
      'editor save orders the task update before the manual-actual update',
      () async {
        const iterations = 200;
        final tasks = TaskRepository(db);
        final timer = TimerService(db);
        final now = DateTime.now();
        final inserted = await tasks.insertTask(
          Task(id: '', title: 'Editor', createdAt: now, updatedAt: now),
        );
        var inversions = 0;
        for (var i = 0; i < iterations; i++) {
          final previousSeq = (await retryable())
              .map((row) => row.seq!)
              .fold<int>(0, (max, seq) => seq > max ? seq : max);
          final actualMinutes = i + 1;
          await db.transaction(() async {
            final current = (await tasks.getTaskById(inserted.id))!;
            await tasks.updateTask(current.copyWith(title: 'Editor $i'));
            await timer.setManualActual(inserted.id, actualMinutes);
          });
          final added = (await retryable())
              .where((row) => row.seq! > previousSeq)
              .toList();
          expect(added, hasLength(2));
          final titleOnly = added.singleWhere(
            (row) =>
                payloadOf(row)['manual_duration_adjustment_min'] !=
                actualMinutes,
          );
          final actual = added.singleWhere(
            (row) =>
                payloadOf(row)['manual_duration_adjustment_min'] ==
                actualMinutes,
          );
          expect(payloadOf(titleOnly)['title'], 'Editor $i');
          if (titleOnly.seq! >= actual.seq!) inversions++;
        }
        // ignore: avoid_print
        print('EDITOR pairs=$iterations inverted=$inversions');
        expect(inversions, 0);
      },
    );

    test('repository-built rows are sequenced with trigger rows', () async {
      final now = DateTime.now().toUtc();
      await db.syncDao.enqueueOperation(
        SyncLogCompanion.insert(
          operationId: 'repository-op',
          entityTableName: 'tasks',
          recordId: 'repository-task',
          operation: 'update',
          payload: '{}',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'trigger-category',
              name: 'Category',
              colorHex: '#4285F4',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final repositoryRow = (await db.syncDao.getOperation('repository-op'))!;
      final triggerRow = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        'trigger-category',
      )).single;
      expect(repositoryRow.seq, isNotNull);
      expect(triggerRow.seq, isNotNull);
      expect(triggerRow.seq!, greaterThan(repositoryRow.seq!));
    });

    test('order ignores mixed created_at precision', () async {
      Future<void> insertRaw(String operationId, String createdAt) =>
          db.customStatement(
            'INSERT INTO sync_log(operation_id, table_name, record_id, '
            'operation, payload, state, attempt_count, created_at, updated_at) '
            "VALUES (?, 'tasks', ?, 'update', '{}', 'pending', 0, ?, ?)",
            [operationId, 'record-$operationId', createdAt, createdAt],
          );

      await insertRaw('op-b-micro', '2026-01-01T00:00:00.123456Z');
      await insertRaw('op-a-milli', '2026-01-01T00:00:00.123Z');

      final operations = await retryable();
      expect(operations.map((row) => row.operationId), [
        'op-b-micro',
        'op-a-milli',
      ]);
      expect(operations.first.seq!, lessThan(operations.last.seq!));
    });
  });
}
