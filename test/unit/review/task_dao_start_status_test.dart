import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final stamp = DateTime.utc(2026, 1, 1);

  Future<void> task(
    String id, {
    DateTime? start,
    DateTime? end,
    String status = 'planned',
    bool inbox = false,
    bool deleted = false,
  }) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          title: id,
          startTime: Value(start),
          endTime: Value(end),
          status: Value(status),
          isInbox: Value(inbox),
          deletedAt: Value(deleted ? stamp : null),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

  // The narrow read repeats the day filter of getTasksBetween in plain SQL. If
  // either changes alone, Review Overview and Weekly history would count
  // different tasks than the rest of the app.
  test('returns exactly the tasks getTasksBetween returns', () async {
    final from = DateTime.utc(2026, 10, 5);
    final to = DateTime.utc(2026, 10, 12);
    DateTime at(int day, [int hour = 9]) => DateTime.utc(2026, 10, day, hour);

    await task('in', start: at(6), end: at(6, 10), status: 'completed');
    await task('in2', start: at(7), end: at(7, 10), status: 'skipped');
    await task('inbox', start: at(6), end: at(6, 10), inbox: true);
    await task('deleted', start: at(6), end: at(6, 10), deleted: true);
    await task('no-end', start: at(6));
    await task('unscheduled');
    await task('spans-in', start: at(3), end: at(6)); // overlaps the range
    await task('ends-at-from', start: at(4), end: from); // not > from
    await task('starts-at-to', start: to, end: at(12, 10)); // not < to
    await task('before', start: at(1), end: at(2));
    await task('after', start: at(20), end: at(21));

    final full = await db.taskDao.getTasksBetween(from, to);
    final narrow = await db.taskDao.getStartAndStatusBetween(from, to);

    String key(DateTime start, String status) =>
        '${start.toUtc().toIso8601String()}|$status';
    final expected = [for (final r in full) key(r.startTime!, r.status)]
      ..sort();
    final actual = [for (final r in narrow) key(r.start, r.status)]..sort();

    expect(actual, expected);
    expect(full.map((r) => r.id).toSet(), {'in', 'in2', 'spans-in'});
  });
}
