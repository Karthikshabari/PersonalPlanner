import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

/// DB-001 measurement on a real device: how often two outbox operations
/// written by one user action share a created_at millisecond, and how often
/// the comparator that orders the outbox at e68bcd5 (parsed created_at, then
/// operation_id) puts the later write first. Measurement only; no assertions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const iterations = 300;

  late Directory directory;
  late AppDatabase db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('outbox_order_device');
    // Same connection setup as AppDatabase.open(), on a temporary file so the
    // device's real planner database is never touched.
    db = AppDatabase(
      NativeDatabase.createInBackground(
        File('${directory.path}/personal_planner.sqlite3'),
        setup: AppDatabase.configureConnection,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  int headChronology(SyncLogRow a, SyncLogRow b) {
    final time = a.createdAt.compareTo(b.createdAt);
    return time == 0 ? a.operationId.compareTo(b.operationId) : time;
  }

  Map<String, Object?> payloadOf(SyncLogRow row) =>
      (jsonDecode(row.payload) as Map).cast<String, Object?>();

  Future<List<SyncLogRow>> outbox() => db.syncDao.getRetryableOperations(
    DateTime.now().toUtc().add(const Duration(days: 1)),
    limit: 1 << 20,
  );

  bool sameMillisecond(SyncLogRow a, SyncLogRow b) =>
      a.createdAt.millisecondsSinceEpoch == b.createdAt.millisecondsSinceEpoch;

  testWidgets('timer stop writes pause then finish', (tester) async {
    final tasks = TaskRepository(db);
    final timer = TimerService(db);
    final sessionIds = <String>[];
    for (var i = 0; i < iterations; i++) {
      final now = DateTime.now();
      final task = await tasks.insertTask(
        Task(id: '', title: 'Device timer $i', createdAt: now, updatedAt: now),
      );
      final started = await timer.start(task.id);
      sessionIds.add(started.session!.id);
      await timer.stop();
    }

    final operations = await outbox();
    var pairs = 0;
    var sameMs = 0;
    var inverted = 0;
    for (final sessionId in sessionIds) {
      final sessionOps = operations.where(
        (row) =>
            row.entityTableName == 'timer_sessions' &&
            row.recordId == sessionId,
      );
      final paused = sessionOps.where(
        (row) => payloadOf(row)['state'] == 'paused',
      );
      final finished = sessionOps.where(
        (row) => payloadOf(row)['state'] == 'finished',
      );
      if (paused.length != 1 || finished.length != 1) continue;
      pairs++;
      if (sameMillisecond(paused.single, finished.single)) sameMs++;
      if (headChronology(finished.single, paused.single) < 0) inverted++;
    }
    // ignore: avoid_print
    print('DEVICE-TIMER pairs=$pairs sameMs=$sameMs inverted=$inverted');
  });

  testWidgets('editor save writes the task update then the manual actual', (
    tester,
  ) async {
    final tasks = TaskRepository(db);
    final timer = TimerService(db);
    final now = DateTime.now();
    final inserted = await tasks.insertTask(
      Task(id: '', title: 'Device editor', createdAt: now, updatedAt: now),
    );
    var pairs = 0;
    var sameMs = 0;
    var inverted = 0;
    for (var i = 0; i < iterations; i++) {
      final before = (await outbox()).map((row) => row.operationId).toSet();
      final actualMinutes = i + 1;
      await db.transaction(() async {
        final current = (await tasks.getTaskById(inserted.id))!;
        await tasks.updateTask(current.copyWith(title: 'Device editor $i'));
        await timer.setManualActual(inserted.id, actualMinutes);
      });
      final added = (await outbox())
          .where((row) => !before.contains(row.operationId))
          .toList();
      final titleOnly = added.where(
        (row) =>
            payloadOf(row)['manual_duration_adjustment_min'] != actualMinutes,
      );
      final actual = added.where(
        (row) =>
            payloadOf(row)['manual_duration_adjustment_min'] == actualMinutes,
      );
      if (titleOnly.length != 1 || actual.length != 1) continue;
      pairs++;
      if (sameMillisecond(titleOnly.single, actual.single)) sameMs++;
      if (headChronology(actual.single, titleOnly.single) < 0) inverted++;
    }
    // ignore: avoid_print
    print('DEVICE-EDITOR pairs=$pairs sameMs=$sameMs inverted=$inverted');
  });
}
