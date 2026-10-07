import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_semantic_equality.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  final reviewDate = DateTime(2026, 10, 7);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, dynamic>> lastPayload(String table) async {
    final rows = await db.select(db.syncLog).get();
    final row = rows.lastWhere((row) => row.entityTableName == table);
    return jsonDecode(row.payload) as Map<String, dynamic>;
  }

  Map<String, dynamic> reviewRow(String id, {Map<String, dynamic>? extra}) {
    const stamp = '2026-10-07T10:00:00.000Z';
    return {
      'id': id,
      'date': '2026-10-07',
      'reflection': 'Remote reflection',
      'energy_level': null,
      'productivity_rating': null,
      'planning_accuracy_rating': null,
      'wins_json': '[]',
      'improvements_json': '[]',
      'created_at': stamp,
      'updated_at': stamp,
      'deleted_at': null,
      ...?extra,
    };
  }

  SyncRemoteChange reviewChange(String id, Map<String, dynamic> payload) =>
      SyncRemoteChange(
        changeId: 1,
        operationId: '00000000-0000-4000-8000-000000000001',
        tableName: 'daily_reviews',
        recordId: id,
        operation: 'update',
        serverVersion: 5,
        serverTimestamp: DateTime.now().toUtc(),
        payload: payload,
      );

  Future<void> applyRemote(SyncRemoteChange change) =>
      db.syncDao.runWithoutOutbound(() => SyncRemoteApplier(db).apply(change));

  test('daily review outbox payload carries mood and task reasons', () async {
    await ReviewRepository(db).saveReviewDraft(
      date: reviewDate,
      mood: 2,
      note: 'Fine',
      taskReasons: {'t1': 'Blocked'},
    );

    final payload = await lastPayload('daily_reviews');
    expect(payload['mood'], 2);
    expect(payload['task_reasons_json'], '{"t1":"Blocked"}');
  });

  test('task outbox payload carries plan_change_reasons_json', () async {
    final now = DateTime.utc(2026, 10, 7, 9);
    await TaskRepository(db).insertTask(
      Task(
        id: '',
        title: 'Planned',
        createdAt: now,
        updatedAt: now,
        planChangeReasons: {'event-1': 'Client asked'},
      ),
    );

    final payload = await lastPayload('tasks');
    expect(payload['plan_change_reasons_json'], '{"event-1":"Client asked"}');
  });

  test(
    'pulled review without the new keys keeps local mood and reasons',
    () async {
      final saved = await ReviewRepository(db).saveReviewDraft(
        date: reviewDate,
        mood: 4,
        note: 'Local',
        taskReasons: {'t1': 'Blocked'},
      );

      await applyRemote(reviewChange(saved.id, reviewRow(saved.id)));

      final row = await db.reviewDao.getDailyReviewById(saved.id);
      expect(row!.reflection, 'Remote reflection');
      expect(row.mood, 4);
      expect(row.taskReasonsJson, '{"t1":"Blocked"}');
    },
  );

  test('pulled review with NULL mood keeps local mood', () async {
    final saved = await ReviewRepository(db).saveReviewDraft(
      date: reviewDate,
      mood: 4,
      note: 'Local',
      taskReasons: {'t1': 'Blocked'},
    );

    await applyRemote(
      reviewChange(
        saved.id,
        reviewRow(saved.id, extra: {'mood': null, 'task_reasons_json': null}),
      ),
    );

    final row = await db.reviewDao.getDailyReviewById(saved.id);
    expect(row!.mood, 4);
    expect(row.taskReasonsJson, '{"t1":"Blocked"}');
  });

  test('invalid mood is rejected', () {
    expect(
      () => SyncPayloadValidator.validate(
        reviewChange('review-1', reviewRow('review-1', extra: {'mood': 5})),
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('semantic equality ignores a missing review field', () {
    final local = reviewRow(
      'review-1',
      extra: {'mood': 2, 'task_reasons_json': '{"a":"x","b":"y"}'},
    );
    final remote = reviewRow(
      'review-1',
      extra: {'task_reasons_json': '{"b":"y","a":"x"}'},
    );

    expect(semanticallyEqualSnapshots('daily_reviews', local, remote), isTrue);
    expect(
      semanticallyEqualSnapshots('daily_reviews', local, {
        ...remote,
        'mood': 3,
      }),
      isFalse,
    );
  });
}
