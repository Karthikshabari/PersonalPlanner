import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/review/domain/review_plan_change.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  final start = DateTime.utc(2026, 9, 14, 10);
  const eventId = '00000000-0000-7000-8000-0000000000a1';

  Task task({Map<String, String> reasons = const {}}) => Task(
    id: '00000000-0000-7000-8000-0000000000a2',
    title: 'Renamed task',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    planTitleHistory: [
      PlanTitleChange(
        id: eventId,
        previousTitle: 'Original task',
        newTitle: 'Renamed task',
        changedAt: start,
      ),
    ],
    displayPlanChangeId: eventId,
    planChangeReasons: reasons,
    createdAt: start,
    updatedAt: start,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() => db.close());

  test('plan-change reasons round-trip through the repository', () async {
    final inserted = await tasks.insertTask(
      task(reasons: {eventId: 'Renamed to match the ticket'}),
    );
    final loaded = (await tasks.getTaskById(inserted.id))!;
    expect(loaded.planChangeReasons, {eventId: 'Renamed to match the ticket'});
  });

  test('ReviewPlanChange.forTask returns the reason for the selected event', () async {
    final inserted = await tasks.insertTask(
      task(reasons: {eventId: 'Renamed to match the ticket'}),
    );
    final loaded = (await tasks.getTaskById(inserted.id))!;
    expect(
      ReviewPlanChange.forTask(loaded)?.reason,
      'Renamed to match the ticket',
    );
  });

  test('a blank reason value makes insertTask throw ArgumentError', () async {
    await expectLater(
      tasks.insertTask(task(reasons: {eventId: '   '})),
      throwsArgumentError,
    );
  });
}
