import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/timer_session.dart';
import '../../../core/utils/date_utils.dart';

/// The only authority for Task.actualDurationMin. The persisted Task field is
/// a cache of completed TimerSession source rows plus a signed manual source;
/// it is never incremented from an incoming cached total.
class TaskActualDurationService {
  TaskActualDurationService(this._db);

  final AppDatabase _db;

  Future<int?> recomputeTask(String taskId) =>
      _db.transaction(() => recomputeTaskInTransaction(taskId));

  Future<void> recomputeTasks(Set<String> taskIds) => _db.transaction(() async {
    for (final taskId in taskIds) {
      await recomputeTaskInTransaction(taskId);
    }
  });

  /// Must be called from the caller's existing database transaction when a
  /// session/source row and its cache are committed atomically.
  Future<int?> recomputeTaskInTransaction(String taskId) async {
    final task = await _db.taskDao.getTaskById(taskId);
    if (task == null) return null;
    final history = await _db.timerDao.getFinishedSessionsForTask(taskId);
    final totalMinutes =
        history.fold<int>(0, (sum, session) => sum + session.durationSec) ~/ 60;
    final actual = history.isEmpty && !task.manualActualSet
        ? null
        : math.max(0, totalMinutes + task.manualDurationAdjustmentMin);
    if (task.actualDurationMin != actual) {
      // This intentionally touches only the derived cache. The task sync
      // trigger excludes actual_duration_min, so there is no semantic
      // revision, updated_at mutation or Task outbox operation.
      await (_db.update(_db.tasks)..where((row) => row.id.equals(taskId)))
          .write(TasksCompanion(actualDurationMin: Value(actual)));
    }
    return actual;
  }

  /// Stores an absolute desired total. A manual zero remains a real source
  /// value through [manualActualSet], rather than being indistinguishable from
  /// untouched legacy data.
  Future<int?> setDisplayedTotal(
    String taskId,
    int minutes, {
    int? expectedRevision,
  }) async {
    if (minutes < 0) {
      throw ArgumentError.value(minutes, 'minutes', 'must not be negative');
    }
    return _db.transaction(() async {
      final task = await _db.taskDao.getTaskById(taskId);
      if (task == null || task.deletedAt != null) {
        throw StateError('Task $taskId not found');
      }
      if (expectedRevision != null && task.revision != expectedRevision) {
        throw StateError(
          'Task $taskId changed while the actual duration was being edited; reload it before saving.',
        );
      }
      final finishedSeconds = await _db.timerDao.getTotalDurationSecForTask(
        taskId,
      );
      final adjustment = minutes - (finishedSeconds ~/ 60);
      final now = DateTime.now();
      // These are semantic source fields, so the normal task trigger records
      // one CAS/outbox mutation and increments its local revision.
      await (_db.update(
        _db.tasks,
      )..where((row) => row.id.equals(taskId))).write(
        TasksCompanion(
          manualDurationAdjustmentMin: Value(adjustment),
          manualActualSet: const Value(true),
          updatedAt: Value(now),
        ),
      );
      return recomputeTaskInTransaction(taskId);
    });
  }

  /// Decodes the persisted intervals. Source/import/sync validators enforce
  /// the complete invariant; this defensive parser also protects analytics
  /// from a corrupt local row.
  static List<TimerWorkInterval> decodeIntervals(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Timer work intervals must be a JSON array.');
    }
    final intervals = <TimerWorkInterval>[];
    DateTime? previousEnd;
    for (final raw in decoded) {
      if (raw is! Map) {
        throw const FormatException('Timer work interval must be an object.');
      }
      final interval = TimerWorkInterval.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (interval.durationSec < 0 ||
          interval.endAt.isBefore(interval.startAt) ||
          interval.durationSec !=
              interval.endAt.difference(interval.startAt).inSeconds ||
          (previousEnd != null && interval.startAt.isBefore(previousEnd))) {
        throw const FormatException(
          'Timer work intervals are not chronological.',
        );
      }
      previousEnd = interval.endAt;
      intervals.add(interval);
    }
    return intervals;
  }

  static Map<String, Object> intervalToJson(TimerWorkInterval interval) => {
    'start_at': interval.startAt.toUtc().toIso8601String(),
    'end_at': interval.endAt.toUtc().toIso8601String(),
    'duration_sec': interval.durationSec,
  };

  static String encodeIntervals(Iterable<TimerWorkInterval> intervals) =>
      jsonEncode([for (final interval in intervals) intervalToJson(interval)]);

  /// Deterministic integer-minute allocation used by Daily Review and
  /// Analytics. It preserves a task's authoritative displayed total over all
  /// calendar buckets, including cross-midnight and sub-minute work.
  static Map<String, int> allocateActualByDate(
    TaskRow task,
    List<TimerSessionRow> completeHistory,
  ) {
    final weights = <String, double>{};
    var totalSeconds = 0;
    for (final session in completeHistory) {
      if (session.deletedAt != null ||
          session.state != TimerSessionState.finished.dbValue ||
          session.endedAt == null) {
        continue;
      }
      totalSeconds += session.durationSec;
      final intervals = decodeIntervals(session.workIntervalsJson);
      if (intervals.isEmpty) {
        _addLegacyWeight(
          weights,
          session.startedAt,
          session.endedAt!,
          session.durationSec,
        );
      } else {
        for (final interval in intervals) {
          _addIntervalWeight(
            weights,
            interval.startAt,
            interval.endAt,
            interval.durationSec,
          );
        }
      }
    }

    final measuredMinutes = totalSeconds ~/ 60;
    final actual = math.max(
      0,
      measuredMinutes + task.manualDurationAdjustmentMin,
    );
    if (completeHistory.isEmpty && !task.manualActualSet) {
      return const <String, int>{};
    }
    final manualDate = isoDateString(task.startTime ?? task.createdAt);
    if (weights.isEmpty) {
      return actual == 0 ? const <String, int>{} : {manualDate: actual};
    }

    if (task.manualDurationAdjustmentMin >= 0) {
      final allocated = _largestRemainder(measuredMinutes, weights);
      if (task.manualDurationAdjustmentMin > 0) {
        allocated[manualDate] =
            (allocated[manualDate] ?? 0) + task.manualDurationAdjustmentMin;
      }
      return allocated;
    }
    return _largestRemainder(actual, weights);
  }

  static void _addLegacyWeight(
    Map<String, double> weights,
    DateTime start,
    DateTime end,
    int durationSec,
  ) {
    if (!end.isAfter(start)) {
      if (durationSec > 0) {
        weights[isoDateString(start)] =
            (weights[isoDateString(start)] ?? 0) + durationSec;
      }
      return;
    }
    _addIntervalWeight(weights, start, end, durationSec);
  }

  static void _addIntervalWeight(
    Map<String, double> weights,
    DateTime start,
    DateTime end,
    int durationSec,
  ) {
    if (durationSec <= 0) return;
    final wallMicros = end.difference(start).inMicroseconds;
    if (wallMicros <= 0) {
      weights[isoDateString(start)] =
          (weights[isoDateString(start)] ?? 0) + durationSec;
      return;
    }
    var cursor = start;
    while (cursor.isBefore(end)) {
      final nextDay = addDays(startOfDay(cursor), 1);
      final segmentEnd = nextDay.isBefore(end) ? nextDay : end;
      final fraction =
          segmentEnd.difference(cursor).inMicroseconds / wallMicros;
      final key = isoDateString(cursor);
      weights[key] = (weights[key] ?? 0) + durationSec * fraction;
      cursor = segmentEnd;
    }
  }

  static Map<String, int> _largestRemainder(
    int total,
    Map<String, double> weights,
  ) {
    if (total <= 0) return <String, int>{};
    final sum = weights.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return <String, int>{};
    final entries = weights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final result = <String, int>{};
    final remainders = <({String key, double value})>[];
    var assigned = 0;
    for (final entry in entries) {
      final raw = total * entry.value / sum;
      final floor = raw.floor();
      result[entry.key] = floor;
      assigned += floor;
      remainders.add((key: entry.key, value: raw - floor));
    }
    remainders.sort((a, b) {
      final value = b.value.compareTo(a.value);
      return value != 0 ? value : a.key.compareTo(b.key);
    });
    for (var index = 0; index < total - assigned; index++) {
      final key = remainders[index % remainders.length].key;
      result[key] = result[key]! + 1;
    }
    return result;
  }
}
