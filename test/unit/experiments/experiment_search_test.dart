import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/domain/experiment_dashboard.dart';
import 'package:personal_planner/features/experiments/domain/experiment_search.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ExperimentRepository experiments;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    experiments = ExperimentRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Experiment> create(
    String name, {
    String? purpose,
    String start = '2026-10-05',
    String end = '2026-10-11',
  }) => experiments.createExperiment(
    name: name,
    purpose: purpose,
    startDate: start,
    endDate: end,
    weekdayTargetMin: 60,
    weekendTargetMin: 90,
    checkInEveryDays: 7,
  );

  Future<Experiment> conclude(
    Experiment e,
    ExperimentOutcome outcome, {
    String? note,
  }) => experiments.concludeExperiment(
    e.id,
    outcome: outcome,
    note: note,
    today: '2026-10-09',
    expectedRevision: e.revision,
  );

  Future<ExperimentDashboard> load() => ExperimentDashboardService(
    db,
    formatDuration: formatMinutes,
  ).load(today: '2026-10-10');

  // Running: "Learn C" (purpose: guitar), "Cold showers".
  // Concluded: "Read daily" (dropped; note: mentions "tennis").
  // Kept: "Morning pages" (purpose: journal), "Stretching".
  Future<ExperimentDashboard> seed() async {
    await create('Learn C', purpose: 'Finish the Guitar book');
    await create('Cold showers');
    final read = await create(
      'Read daily',
      start: '2026-09-01',
      end: '2026-09-30',
    );
    await conclude(read, ExperimentOutcome.drop, note: 'More tennis instead');
    final pages = await create(
      'Morning pages',
      purpose: 'A journal habit',
      start: '2026-09-04',
      end: '2026-10-03',
    );
    await conclude(pages, ExperimentOutcome.keep);
    final stretch = await create(
      'Stretching',
      start: '2026-09-04',
      end: '2026-10-03',
    );
    await conclude(stretch, ExperimentOutcome.keep);
    return load();
  }

  test('an empty needle gives null', () async {
    expect(matchExperiments(await seed(), ''), isNull);
  });

  test('matches the name, ignoring case', () async {
    final dashboard = await seed();
    final matches = matchExperiments(dashboard, 'cold sh')!;
    expect(matches.ids, hasLength(1));
    expect(matches.running, 1);
    expect(matches.kept, 0);
    expect(matches.concluded, 0);
  });

  test('matches the description', () async {
    final dashboard = await seed();
    final guitar = matchExperiments(dashboard, 'guitar book')!;
    expect(guitar.running, 1);
    final journal = matchExperiments(dashboard, 'journal')!;
    expect(journal.kept, 1);
  });

  test('does not match the conclusion note', () async {
    final dashboard = await seed();
    final matches = matchExperiments(dashboard, 'tennis')!;
    expect(matches.ids, isEmpty);
    expect(matches.concluded, 0);
  });

  test(
    'counts running, kept and concluded matches like the card rows',
    () async {
      final dashboard = await seed();
      // The letter 'e' is in every name, so every experiment matches.
      final all = matchExperiments(dashboard, 'e')!;
      expect(all.ids, hasLength(5));
      expect(all.running, dashboard.runningCount);
      expect(all.kept, dashboard.keptCount);
      expect(all.concluded, dashboard.concludedCount);
      expect(all.kept, 2);
    },
  );

  test('the kept count follows the experiment id', () async {
    final dashboard = await seed();
    final matches = matchExperiments(dashboard, 'stretching')!;
    expect(matches.ids, hasLength(1));
    expect(matches.kept, 1);
    // A kept experiment is also a concluded one, as on the card.
    expect(matches.concluded, 1);
    expect(matches.running, 0);
  });

  test('is contiguous: a different word order does not match', () async {
    final dashboard = await seed();
    expect(matchExperiments(dashboard, 'showers cold')!.ids, isEmpty);
  });
}
