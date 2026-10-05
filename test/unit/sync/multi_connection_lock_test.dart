import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/data/timer_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';
import 'package:sqlite3/open.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  // Two connections to one file are the point of this test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('multi-connection writes (DB-031)', () {
    test(
      'concurrent timer stop from two connections does not fail with database '
      'is locked',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('planner_locks');
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File(p.join(tempDir.path, 'planner.sqlite3'));
        AppDatabase open() => AppDatabase(
          NativeDatabase.createInBackground(
            file,
            setup: AppDatabase.configureConnection,
            isolateSetup: _overrideSqliteLibrary,
          ),
        );

        // The main app connection creates the file before the second engine
        // (Android action isolate / Linux reminder worker) opens it.
        final a = open();
        addTearDown(a.close);
        final now = DateTime.now().toUtc();
        final task = await TaskRepository(a).insertTask(
          Task(id: '', title: 'Shared', createdAt: now, updatedAt: now),
        );
        final owner = await TimerRepository(a).localDeviceId();
        final b = open();
        addTearDown(b.close);
        await b.customSelect('SELECT 1').get();

        final timerA = TimerService(a);
        final timerB = TimerService(b);
        final lockFailures = <Object>[];
        final otherErrors = <Object>[];
        for (var i = 0; i < 50; i++) {
          final started = await timerA.start(task.id);
          final sessionId = started.session!.id;
          final outcomes = await Future.wait([
            _capture(timerA.stop()),
            _capture(
              timerB.stopSession(sessionId, expectedOwnerDeviceId: owner),
            ),
          ]);
          for (final error in outcomes.whereType<Object>()) {
            (_isLockFailure(error) ? lockFailures : otherErrors).add(error);
          }
        }

        expect(lockFailures, isEmpty);
        expect(otherErrors, isEmpty);
      },
    );
  });
}

/// Completes with the error thrown by [action], or null when it succeeds.
Future<Object?> _capture(Future<Object?> action) async {
  try {
    await action;
    return null;
  } catch (error) {
    return error;
  }
}

/// Errors from a background connection arrive wrapped, so the remote cause is
/// matched through its message as well as by type.
bool _isLockFailure(Object error) {
  if (error is SqliteException) {
    final code = error.extendedResultCode;
    return code == 5 || code == 517 || error.resultCode == 5;
  }
  return RegExp(r'SqliteException\((5|517)\)|database is locked')
      .hasMatch('$error');
}

void _overrideSqliteLibrary() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}
