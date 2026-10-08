import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/sync/data/remote_apply.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_semantic_equality.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  final week = DateTime(2026, 9, 28);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, dynamic>> lastPayload() async {
    final rows = await db.select(db.syncLog).get();
    final row = rows.lastWhere(
      (row) => row.entityTableName == 'weekly_reviews',
    );
    return jsonDecode(row.payload) as Map<String, dynamic>;
  }

  Map<String, dynamic> weeklyRow(String id, {Map<String, dynamic>? extra}) {
    const stamp = '2026-10-04T10:00:00.000Z';
    return {
      'id': id,
      'week_start_date': '2026-09-28',
      'reflection': 'Remote note',
      'overall_rating': null,
      'goals_met_json': '[]',
      'goals_missed_json': '[]',
      'next_week_focus_json': '[]',
      'created_at': stamp,
      'updated_at': stamp,
      'deleted_at': null,
      ...?extra,
    };
  }

  SyncRemoteChange weeklyChange(String id, Map<String, dynamic> payload) =>
      SyncRemoteChange(
        changeId: 1,
        operationId: '00000000-0000-4000-8000-000000000101',
        tableName: 'weekly_reviews',
        recordId: id,
        operation: 'update',
        serverVersion: 5,
        serverTimestamp: DateTime.now().toUtc(),
        payload: payload,
      );

  Future<void> applyRemote(SyncRemoteChange change) =>
      db.syncDao.runWithoutOutbound(() => SyncRemoteApplier(db).apply(change));

  Future<String> saveLocal() async {
    final saved = await ReviewRepository(db).saveWeeklyReviewDraft(
      weekStart: week,
      mood: 4,
      feeling: 'Proud',
      note: 'Local note',
    );
    return saved.id;
  }

  test('weekly review outbox payload carries mood and feeling', () async {
    await saveLocal();

    final payload = await lastPayload();
    expect(payload['mood'], 4);
    expect(payload['feeling'], 'Proud');
  });

  test('pulled weekly review without the new keys keeps them', () async {
    final id = await saveLocal();

    await applyRemote(weeklyChange(id, weeklyRow(id)));

    final row = await db.reviewDao.getWeeklyReviewById(id);
    expect(row!.reflection, 'Remote note');
    expect(row.mood, 4);
    expect(row.feeling, 'Proud');
  });

  test('pulled weekly review with NULL mood and feeling keeps them', () async {
    final id = await saveLocal();

    await applyRemote(
      weeklyChange(id, weeklyRow(id, extra: {'mood': null, 'feeling': null})),
    );

    final row = await db.reviewDao.getWeeklyReviewById(id);
    expect(row!.mood, 4);
    expect(row.feeling, 'Proud');
  });

  test('pulled empty feeling clears the local feeling', () async {
    final id = await saveLocal();

    await applyRemote(
      weeklyChange(id, weeklyRow(id, extra: {'mood': 2, 'feeling': ''})),
    );

    final row = await db.reviewDao.getWeeklyReviewById(id);
    expect(row!.mood, 2);
    expect(row.feeling, '');
  });

  test('invalid weekly mood and over-long feeling are rejected', () {
    expect(
      () => SyncPayloadValidator.validate(
        weeklyChange('w1', weeklyRow('w1', extra: {'mood': 5})),
      ),
      throwsA(isA<SyncValidationException>()),
    );
    expect(
      () => SyncPayloadValidator.validate(
        weeklyChange('w1', weeklyRow('w1', extra: {'feeling': 'x' * 201})),
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('semantic equality ignores a missing weekly mood or feeling', () {
    final local = weeklyRow('w1', extra: {'mood': 2, 'feeling': 'Calm'});
    final remote = weeklyRow('w1');

    expect(semanticallyEqualSnapshots('weekly_reviews', local, remote), isTrue);
    expect(
      semanticallyEqualSnapshots('weekly_reviews', local, {
        ...remote,
        'feeling': 'Tired',
      }),
      isFalse,
    );
  });
}
