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

  SyncLogRow operation(
    String kind,
    Map<String, dynamic> payload, {
    String table = 'tasks',
  }) => SyncLogRow(
    operationId: 'op',
    entityTableName: table,
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

  test('experiments and check-ins are named, not shown as a raw record id', () {
    expect(syncTableLabel('experiments'), 'Experiment');
    expect(syncTableLabel('experiment_check_ins'), 'Experiment check-in');
    expect(
      syncRecordName('experiments', {
        'id': 'e1234567',
        'purpose': 'Read before bed',
      }),
      'Read before bed',
    );
    expect(
      syncRecordName('experiments', {
        'id': 'e1234567',
        'start_date': '2026-10-01',
        'end_date': '2026-10-14',
      }),
      '2026-10-01 to 2026-10-14',
    );
    expect(
      syncRecordName('experiment_check_ins', {
        'id': 'c1',
        'slot_date': '2026-10-07',
      }),
      '2026-10-07',
    );
  });

  test('live tags are labelled Tag; Legacy stays on retired metadata', () {
    expect(syncTableLabel('tags'), 'Tag');
    expect(syncTableLabel('task_tags'), 'Legacy metadata link');
    expect(
      syncOperationSummary(
        operation('update', {'name': 'deep-work'}, table: 'tags'),
      ),
      'Update · Tag · deep-work',
    );
  });

  test('conflict lines show both values for the first two changes only', () {
    final lines = conflictDifferenceLines(
      SyncConflictRow(
        id: 'c',
        operationId: 'op',
        entityTableName: 'tasks',
        recordId: 't',
        localSnapshot: jsonEncode({
          'id': 't',
          'title': 'Write report',
          'status': 'done',
          'tag_id': 'a',
          'notes': 'x',
          'updated_at': '2026-10-14T10:00:00Z',
          'server_version': 3,
        }),
        remoteSnapshot: jsonEncode({
          'id': 't',
          'title': 'Write the report',
          'status': 'planned',
          'tag_id': 'b',
          'notes': 'y',
          'updated_at': '2026-10-14T11:00:00Z',
          'server_version': 5,
        }),
        expectedServerVersion: 3,
        actualServerVersion: 5,
        createdAt: now.toUtc(),
      ),
    );

    expect(lines, [
      'Title: Write report (this device) · Write the report (other device)',
      'Status: done (this device) · planned (other device)',
      '+2 more changes',
    ]);
    expect(lines.join(), isNot(contains('server_version')));
    expect(lines.join(), isNot(contains('Server version')));
  });

  test('a changed tag is labelled Tag and a deletion reads yes or no', () {
    final lines = conflictDifferenceLines(
      conflict(
        {'tag_id': 'a', 'deleted_at': null},
        {'tag_id': null, 'deleted_at': '2026-10-14T11:00:00Z'},
      ),
    );

    expect(lines, [
      'Tag: a (this device) · none (other device)',
      'Deleted: no (this device) · yes (other device)',
    ]);
  });
}
