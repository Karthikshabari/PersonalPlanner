import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/day_contexts_table.dart';
import '../tables/experiments_table.dart';
import '../tables/tags_table.dart';
import '../tables/tasks_table.dart';

part 'experiment_dao.g.dart';

/// An experiment together with the tag it is linked to.
class ExperimentWithTag {
  const ExperimentWithTag({required this.experiment, required this.tag});

  final ExperimentRow experiment;
  final TagRow tag;
}

@DriftAccessor(
  tables: [Experiments, ExperimentCheckIns, Tags, DayContexts, Tasks],
)
class ExperimentDao extends DatabaseAccessor<AppDatabase>
    with _$ExperimentDaoMixin {
  ExperimentDao(super.db);

  /// All non-deleted experiments with their tag row, earliest start first.
  Stream<List<ExperimentWithTag>> watchExperiments() {
    final query =
        select(experiments)
            .join([innerJoin(tags, tags.id.equalsExp(experiments.tagId))])
          ..where(experiments.deletedAt.isNull())
          ..orderBy([
            OrderingTerm.asc(experiments.startDate),
            OrderingTerm.asc(experiments.id),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ExperimentWithTag(
            experiment: row.readTable(experiments),
            tag: row.readTable(tags),
          ),
      ],
    );
  }

  Future<ExperimentRow?> getExperimentById(String id) =>
      (select(experiments)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<ExperimentRow?> getExperimentByTagId(String tagId) => (select(
    experiments,
  )..where((e) => e.tagId.equals(tagId))).getSingleOrNull();

  Future<void> insertExperiment(ExperimentsCompanion entry) =>
      into(experiments).insert(entry);

  /// Writes without `serverVersion`, like `TagDao.updateTag`: that column
  /// changes only through acknowledged or pulled remote state.
  Future<bool> updateExperiment(ExperimentRow row) async {
    final count = await (update(experiments)..where((e) => e.id.equals(row.id)))
        .write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  Future<List<ExperimentCheckInRow>> getCheckInsForExperiment(
    String experimentId,
  ) => _checkInsQuery(experimentId).get();

  Stream<List<ExperimentCheckInRow>> watchCheckInsForExperiment(
    String experimentId,
  ) => _checkInsQuery(experimentId).watch();

  SimpleSelectStatement<$ExperimentCheckInsTable, ExperimentCheckInRow>
  _checkInsQuery(String experimentId) {
    return select(experimentCheckIns)
      ..where((c) => c.experimentId.equals(experimentId) & c.deletedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.slotDate)]);
  }

  Future<ExperimentCheckInRow?> getCheckInById(String id) => (select(
    experimentCheckIns,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> insertCheckIn(ExperimentCheckInsCompanion entry) =>
      into(experimentCheckIns).insert(entry);
}
