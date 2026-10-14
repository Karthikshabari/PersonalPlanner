import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/sync/presentation/screens/sync_settings_screen.dart';

/// QA Phase 3 P5/P6 labels on the Sync screen.
void main() {
  final now = DateTime(2026, 10, 14, 12);

  SyncConflictRow conflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) => SyncConflictRow(
    id: 'c',
    operationId: 'op',
    entityTableName: 'tasks',
    recordId: 't',
    localSnapshot: jsonEncode(local),
    remoteSnapshot: jsonEncode(remote),
    createdAt: now.toUtc(),
  );

  SyncLogRow operation(String kind, Map<String, dynamic> payload) => SyncLogRow(
    operationId: 'op',
    entityTableName: 'tasks',
    recordId: 'task-1',
    operation: kind,
    payload: jsonEncode(payload),
    state: 'error',
    attemptCount: 7,
    nextAttemptAt: DateTime(2026, 10, 14, 14, 5).toUtc(),
    lastError: 'Refused [server - 42501] permission denied',
    createdAt: now.toUtc(),
    updatedAt: now.toUtc(),
  );

  test('conflict line shows when each side changed, 24-hour clock', () {
    final line = conflictChangedLine(
      conflict(
        {
          'title': 'A',
          'updated_at': now
              .subtract(const Duration(minutes: 2))
              .toUtc()
              .toIso8601String(),
        },
        {
          'title': 'B',
          'updated_at': DateTime(
            2026,
            10,
            13,
            21,
            47,
          ).toUtc().toIso8601String(),
        },
      ),
      now: now,
    );
    expect(
      line,
      'This device: changed 2 minutes ago · '
      'Another device: changed Yesterday at 21:47',
    );
  });

  test('conflict line without a change time says so', () {
    expect(
      conflictChangedLine(conflict({'title': 'A'}, {'title': 'B'}), now: now),
      'This device: change time unknown · Another device: change time unknown',
    );
  });

  test('operation summary names the attempt and the record', () {
    expect(
      syncOperationSummary(operation('insert', {'title': 'Write report'})),
      'Create · Task · Write report',
    );
    expect(
      syncOperationSummary(operation('delete', {})),
      'Delete · Task · task-1',
    );
    expect(
      syncRetryingLine(operation('update', {'title': 'x'})),
      'Tried 7 times · next try 14:05\nRefused [server - 42501] permission denied',
    );
  });
}
