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

/// The columns of one tagged block that the Experiments card sums up.
class TaggedBlockRow {
  const TaggedBlockRow({
    required this.startTime,
    required this.status,
    required this.actualDurationMin,
    required this.estimatedDurationMin,
  });

  final DateTime startTime;
  final String status;
  final int? actualDurationMin;
  final int? estimatedDurationMin;
}

/// The range query of ED41. Its first three conditions are literal SQL in the
/// exact form of the partial index `idx_tasks_tag_date`, so SQLite can prove
/// the query implies the index's WHERE clause and uses the index; a bound
/// value (Drift's `isInbox.equals(false)`) would not match. The bound values
/// are the tag id and the half-open UTC range.
const taggedBlocksInRangeSql =
    'SELECT start_time, status, actual_duration_min, estimated_duration_min '
    'FROM tasks '
    'WHERE deleted_at IS NULL AND is_inbox = 0 AND tag_id IS NOT NULL '
    'AND tag_id = ? AND start_time >= ? AND start_time < ?';

/// A kept experiment's tag and the instant its blocks start to count from (the
/// start of its start date in planner time).
typedef KeptTagWindow = ({String tagId, DateTime countedFrom});

/// The done rule of `groupBlocksByDay` (ED10, ED45) in SQL: a recorded Actual
/// (negative counts 0), otherwise the planned duration.
const keptDoneMinutesExpression =
    'CASE WHEN t.actual_duration_min IS NOT NULL '
    'THEN MAX(t.actual_duration_min, 0) '
    'ELSE MAX(COALESCE(t.estimated_duration_min, 0), 0) END';

/// Completed minutes per tag and bucket. Used twice: 9 week buckets, 7 day
/// buckets. Bound values, in order: `(tag_id, counted_from)` per kept
/// experiment, then `(bucket, range_start, range_end)` per bucket. The first
/// three WHERE conditions are literal SQL in the form of the partial index
/// `idx_tasks_tag_date` (see [taggedBlocksInRangeSql]).
String keptCompletedMinutesSql(int keptCount, int bucketCount) =>
    'WITH kept(tag_id, counted_from) AS (VALUES '
    '${List.filled(keptCount, '(?, ?)').join(', ')}), '
    'buckets(bucket, range_start, range_end) AS (VALUES '
    '${List.filled(bucketCount, '(?, ?, ?)').join(', ')}) '
    'SELECT t.tag_id AS tag_id, b.bucket AS bucket, '
    'SUM($keptDoneMinutesExpression) AS done_min '
    'FROM kept k CROSS JOIN buckets b '
    'JOIN tasks t ON t.tag_id = k.tag_id '
    'AND t.start_time >= b.range_start AND t.start_time < b.range_end '
    'WHERE t.deleted_at IS NULL AND t.is_inbox = 0 AND t.tag_id IS NOT NULL '
    "AND t.status = 'completed' AND t.start_time >= k.counted_from "
    'GROUP BY t.tag_id, b.bucket';

/// Planned minutes per tag from the start of today to the next week start.
/// Bound values, in order: the tag ids, then the half-open UTC range.
String keptPlannedMinutesSql(int tagCount) =>
    'SELECT tag_id, SUM(MAX(COALESCE(estimated_duration_min, 0), 0)) AS planned_min '
    'FROM tasks '
    'WHERE deleted_at IS NULL AND is_inbox = 0 AND tag_id IS NOT NULL '
    'AND tag_id IN (${List.filled(tagCount, '?').join(', ')}) '
    "AND status IN ('planned', 'in_progress') "
    'AND start_time >= ? AND start_time < ? '
    'GROUP BY tag_id';

@DriftAccessor(
  tables: [Experiments, ExperimentCheckIns, Tags, DayContexts, Tasks],
)
class ExperimentDao extends DatabaseAccessor<AppDatabase>
    with _$ExperimentDaoMixin {
  ExperimentDao(super.db);

  /// All non-deleted experiments with their tag row, earliest start first.
  Stream<List<ExperimentWithTag>> watchExperiments() =>
      _experimentsQuery().watch().map(_withTags);

  /// The same list as [watchExperiments], read once.
  Future<List<ExperimentWithTag>> getExperiments() async =>
      _withTags(await _experimentsQuery().get());

  JoinedSelectStatement<HasResultSet, dynamic> _experimentsQuery() =>
      select(experiments)
          .join([innerJoin(tags, tags.id.equalsExp(experiments.tagId))])
        ..where(experiments.deletedAt.isNull())
        ..orderBy([
          OrderingTerm.asc(experiments.startDate),
          OrderingTerm.asc(experiments.id),
        ]);

  List<ExperimentWithTag> _withTags(List<TypedResult> rows) => [
    for (final row in rows)
      ExperimentWithTag(
        experiment: row.readTable(experiments),
        tag: row.readTable(tags),
      ),
  ];

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

  /// The non-deleted check-ins of every experiment in [experimentIds], read
  /// with one query. Earliest slot first within an experiment.
  Future<List<ExperimentCheckInRow>> getCheckInsForExperiments(
    List<String> experimentIds,
  ) {
    if (experimentIds.isEmpty) return Future.value(const []);
    return (select(experimentCheckIns)
          ..where(
            (c) => c.experimentId.isIn(experimentIds) & c.deletedAt.isNull(),
          )
          ..orderBy([
            (c) => OrderingTerm.asc(c.experimentId),
            (c) => OrderingTerm.asc(c.slotDate),
          ]))
        .get();
  }

  Future<ExperimentCheckInRow?> getCheckInById(String id) => (select(
    experimentCheckIns,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> insertCheckIn(ExperimentCheckInsCompanion entry) =>
      into(experimentCheckIns).insert(entry);

  /// The non-deleted, non-Inbox blocks that carry [tagId] and start at or
  /// after [rangeStart] and before [rangeEnd] (ED41). One indexed range
  /// query; the planner-local day of each row is decided later in Dart.
  Future<List<TaggedBlockRow>> taggedBlocksInRange(
    String tagId,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    final rows = await customSelect(
      taggedBlocksInRangeSql,
      variables: [
        Variable<String>(tagId),
        Variable<String>(_iso(rangeStart)),
        Variable<String>(_iso(rangeEnd)),
      ],
      readsFrom: {tasks},
    ).get();
    return [
      for (final row in rows)
        TaggedBlockRow(
          startTime: DateTime.parse(row.read<String>('start_time')),
          status: row.read<String>('status'),
          actualDurationMin: row.readNullable<int>('actual_duration_min'),
          estimatedDurationMin: row.readNullable<int>('estimated_duration_min'),
        ),
    ];
  }

  /// Completed minutes per tag and bucket for the [kept] experiments. Each
  /// bucket is a half-open [start, end) range; the result is keyed by tag id,
  /// then by the bucket's index in [buckets]. Blocks before a tag's
  /// `countedFrom` are ignored. Empty buckets are absent from the maps.
  Future<Map<String, Map<int, int>>> keptCompletedMinutes(
    List<KeptTagWindow> kept,
    List<(DateTime, DateTime)> buckets,
  ) async {
    if (kept.isEmpty || buckets.isEmpty) return const {};
    final rows = await customSelect(
      keptCompletedMinutesSql(kept.length, buckets.length),
      variables: [
        for (final window in kept) ...[
          Variable<String>(window.tagId),
          Variable<String>(_iso(window.countedFrom)),
        ],
        for (var i = 0; i < buckets.length; i++) ...[
          Variable<int>(i),
          Variable<String>(_iso(buckets[i].$1)),
          Variable<String>(_iso(buckets[i].$2)),
        ],
      ],
      readsFrom: {tasks},
    ).get();
    final result = <String, Map<int, int>>{};
    for (final row in rows) {
      final byBucket = result.putIfAbsent(row.read<String>('tag_id'), () => {});
      byBucket[row.read<int>('bucket')] = row.read<int>('done_min');
    }
    return result;
  }

  /// Planned and in-progress minutes per tag for blocks that start in
  /// [from, to). Tags without such blocks are absent from the map.
  Future<Map<String, int>> keptPlannedMinutes(
    List<String> tagIds, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (tagIds.isEmpty) return const {};
    final rows = await customSelect(
      keptPlannedMinutesSql(tagIds.length),
      variables: [
        for (final tagId in tagIds) Variable<String>(tagId),
        Variable<String>(_iso(from)),
        Variable<String>(_iso(to)),
      ],
      readsFrom: {tasks},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('tag_id'): row.read<int>('planned_min'),
    };
  }

  /// The dates in [firstDate]..[lastDate] (inclusive, `yyyy-MM-dd`) that have
  /// a non-deleted Leave or Holiday day context.
  Future<Set<String>> leaveOrHolidayDates(
    String firstDate,
    String lastDate,
  ) async {
    final rows = await customSelect(
      'SELECT date FROM day_contexts '
      "WHERE deleted_at IS NULL AND kind IN ('leave', 'holiday') "
      'AND date >= ? AND date <= ?',
      variables: [Variable<String>(firstDate), Variable<String>(lastDate)],
      readsFrom: {dayContexts},
    ).get();
    return {for (final row in rows) row.read<String>('date')};
  }

  /// Same text form as `TaskDao._iso`, which the stored instants use.
  String _iso(DateTime instant) => instant.toUtc().toIso8601String();
}
