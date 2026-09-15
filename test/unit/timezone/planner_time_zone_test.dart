import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/missed_at.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  setUp(() => PlannerTimeZone.initialize(identifier: 'America/New_York'));

  test('calendar-day arithmetic preserves local midnight across DST start', () {
    final before = parseIsoDate('2026-03-08');
    final after = addDays(before, 1);

    expect(isoDateString(before), '2026-03-08');
    expect(isoDateString(after), '2026-03-09');
    expect(startOfDay(after).hour, 0);
    expect(after.difference(before).inHours, 23);
  });

  test('calendar-day arithmetic preserves local midnight across DST end', () {
    final before = parseIsoDate('2026-11-01');
    final after = addDays(before, 1);

    expect(isoDateString(after), '2026-11-02');
    expect(startOfDay(after).hour, 0);
    expect(after.difference(before).inHours, 25);
  });

  test('missed marker parser treats the legacy minute shape as UTC', () {
    final instant = MissedAtCodec.parse('2026-09-14T18:30');
    expect(instant, DateTime.utc(2026, 9, 14, 18, 30));
    expect(MissedAtCodec.normalize('2026-09-14T18:30Z'), '2026-09-14T18:30');
    expect(
      MissedAtCodec.normalize('2026-09-14T18:30+05:30'),
      '2026-09-14T13:00',
    );
    expect(MissedAtCodec.parse('2026-02-30T18:30'), isNull);
    expect(MissedAtCodec.parse('not-a-marker'), isNull);
  });

  test(
    'zone-less missed marker remains stable across two file reopens',
    () async {
      PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');
      final directory = await Directory.systemTemp.createTemp(
        'planner_missed_',
      );
      final file = File('${directory.path}/planner.sqlite');
      AppDatabase? db;
      try {
        db = AppDatabase(NativeDatabase(file));
        final task = await TaskRepository(db).insertTask(
          Task(
            id: '',
            title: 'Stable marker',
            missedAt: '2026-09-14T18:30',
            createdAt: DateTime.utc(2026, 9, 14),
            updatedAt: DateTime.utc(2026, 9, 14),
          ),
        );
        await db.close();
        db = null;

        for (var reopen = 0; reopen < 2; reopen++) {
          db = AppDatabase(NativeDatabase(file));
          expect(
            (await TaskRepository(db).getTaskById(task.id))?.missedAt,
            '2026-09-14T18:30',
          );
          await db.close();
          db = null;
        }
      } finally {
        await db?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'planner display converts a UTC marker across a local date boundary',
    () {
      PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');
      final local = PlannerTimeZone.toPlannerLocal(
        MissedAtCodec.parse('2026-09-14T18:30')!,
      );
      expect(local.year, 2026);
      expect(local.month, 9);
      expect(local.day, 15);
      expect(local.hour, 0);
    },
  );
}
