import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/category.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../day_context/data/day_context_repository.dart';
import '../../timeline/data/task_repository.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import 'analytics_models.dart';

/// Loads Insights from local history in bounded range passes. There is no
/// per-calendar-day database query: day slicing and grouping happen in memory.
class InsightsService {
  InsightsService(this._db);

  final AppDatabase _db;

  Future<InsightsSnapshot> compute({
    required DateTime weekStart,
    DateTime? now,
    // Retained for source compatibility with older callers. The consistency
    // history is now always the rolling year on every form factor.
    int desktopMonthCount = 12,
  }) => _db.transaction(() async {
    final effectiveNow = now ?? DateTime.now();
    final today = startOfDay(effectiveNow);
    final currentWeekStart = startOfWeek(today);
    final selectedWeek = startOfWeek(weekStart);
    if (selectedWeek.isAfter(currentWeekStart)) {
      throw ArgumentError('Insights cannot navigate beyond the current week.');
    }

    final consistencyStart = addDays(today, -364);
    final consistencyEnd = addDays(today, 1);
    final baselineStart = addDays(selectedWeek, -28);
    final actualRangeStart = baselineStart.isBefore(consistencyStart)
        ? baselineStart
        : consistencyStart;
    final actualRangeEnd = addDays(today, 1);
    final currentWeekEnd = addDays(currentWeekStart, 7);
    final plannedRangeEnd = currentWeekEnd.isAfter(consistencyEnd)
        ? currentWeekEnd
        : consistencyEnd;

    // One planned-history query supports the visible calendar plus accurate
    // all-history current/best streaks. It retains the DAO's canonical active,
    // scheduled, interval-overlap predicate.
    final plannedRows = await _db.taskDao.getTasksBetween(
      PlannerTimeZone.calendarDate(2000, 1, 1),
      plannedRangeEnd,
    );
    final plannedTasks = plannedRows
        .map(TaskRepository.fromRow)
        .toList(growable: false);

    final overlappingSessions =
        await (_db.select(_db.timerSessions)..where(
              (session) =>
                  session.deletedAt.isNull() &
                  session.state.equals('finished') &
                  session.endedAt.isNotNull() &
                  session.startedAt.isSmallerThanValue(
                    actualRangeEnd.toUtc().toIso8601String(),
                  ) &
                  session.endedAt.isBiggerThanValue(
                    actualRangeStart.toUtc().toIso8601String(),
                  ),
            ))
            .get();

    final actualTaskIds = <String>{
      for (final row in plannedRows)
        if (row.startTime != null &&
            !row.startTime!.isBefore(actualRangeStart) &&
            row.startTime!.isBefore(actualRangeEnd))
          row.id,
      for (final session in overlappingSessions) session.taskId,
    };
    final actualRows = actualTaskIds.isEmpty
        ? const <TaskRow>[]
        : await (_db.select(
            _db.tasks,
          )..where((task) => task.id.isIn(actualTaskIds))).get();
    final finishedHistory = actualTaskIds.isEmpty
        ? const <TimerSessionRow>[]
        : await (_db.select(_db.timerSessions)..where(
                (session) =>
                    session.deletedAt.isNull() &
                    session.state.equals('finished') &
                    session.endedAt.isNotNull() &
                    session.taskId.isIn(actualTaskIds),
              ))
              .get();
    final historyByTask = <String, List<TimerSessionRow>>{};
    for (final session in finishedHistory) {
      historyByTask
          .putIfAbsent(session.taskId, () => <TimerSessionRow>[])
          .add(session);
    }
    final actualSlices = <ActualTimeSlice>[];
    for (final task in actualRows) {
      final allocation = TaskActualDurationService.allocateActualByDate(
        task,
        historyByTask[task.id] ?? const <TimerSessionRow>[],
      );
      for (final entry in allocation.entries) {
        final date = parseIsoDate(entry.key);
        if (entry.value > 0 &&
            !date.isBefore(actualRangeStart) &&
            date.isBefore(actualRangeEnd)) {
          actualSlices.add(
            ActualTimeSlice(taskId: task.id, date: date, minutes: entry.value),
          );
        }
      }
    }

    final categoryRows = await _db.select(_db.categories).get();
    final categories = categoryRows
        .map(
          (row) => Category(
            id: row.id,
            name: row.name,
            colorHex: row.colorHex,
            sortOrder: row.sortOrder,
            isFocus: row.isFocus,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
          ),
        )
        .toList(growable: false);

    final firstHistoryDay = plannedTasks.isEmpty
        ? consistencyStart
        : plannedTasks
              .map((task) => startOfDay(task.startTime!))
              .reduce((left, right) => left.isBefore(right) ? left : right);
    final contextRows =
        await (_db.select(_db.dayContexts)..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.date.isBiggerOrEqualValue(
                    isoDateString(firstHistoryDay),
                  ) &
                  row.date.isSmallerThanValue(isoDateString(consistencyEnd)),
            ))
            .get();

    return InsightsCalculator.calculate(
      source: InsightsSourceData(
        plannedTasks: plannedTasks,
        actualTasks: actualRows
            .map(TaskRepository.fromRow)
            .toList(growable: false),
        actualSlices: actualSlices,
        categories: categories,
        dayContexts: contextRows
            .map(DayContextRepository.fromRow)
            .toList(growable: false),
      ),
      now: effectiveNow,
      selectedWeekStart: selectedWeek,
      consistencyStart: consistencyStart,
    );
  });
}

/// Pure duration-weighted Insights formulas, independent of Flutter and SQL.
abstract final class InsightsCalculator {
  static InsightsSnapshot calculate({
    required InsightsSourceData source,
    required DateTime now,
    required DateTime selectedWeekStart,
    required DateTime consistencyStart,
  }) {
    final today = startOfDay(now);
    final consistencyEnd = addDays(today, 1);
    final weekStart = startOfWeek(selectedWeekStart);
    final weekEnd = addDays(weekStart, 7);
    final firstTaskDay = source.plannedTasks.isEmpty
        ? consistencyStart
        : source.plannedTasks
              .map((task) => startOfDay(task.startTime!))
              .reduce((left, right) => left.isBefore(right) ? left : right);
    final historyStart = firstTaskDay.isBefore(consistencyStart)
        ? firstTaskDay
        : consistencyStart;
    final actualByDate = <String, int>{};
    for (final slice in source.actualSlices) {
      final key = isoDateString(slice.date);
      actualByDate[key] = (actualByDate[key] ?? 0) + slice.minutes;
    }
    final contexts = {
      for (final context in source.dayContexts) context.date: context.kind,
    };
    final allDays = <ConsistencyDay>[];
    for (
      var date = historyStart;
      date.isBefore(consistencyEnd);
      date = addDays(date, 1)
    ) {
      final totals = _plannedTotals(
        source.plannedTasks,
        InsightDateRange(date, addDays(date, 1)),
      );
      allDays.add(
        ConsistencyDay(
          date: date,
          plannedMinutes: totals.planned,
          completedPlannedMinutes: totals.completed,
          actualMinutes: actualByDate[isoDateString(date)] ?? 0,
          context: contexts[isoDateString(date)],
          isFuture: date.isAfter(today),
        ),
      );
    }
    final visibleDays = allDays
        .where((day) => !day.date.isBefore(consistencyStart))
        .toList(growable: false);
    final streaks = calculateStreaks(allDays);
    final weekRange = InsightDateRange(weekStart, weekEnd);
    final weekPlanned = _plannedTotals(source.plannedTasks, weekRange);
    final weekActual = _actualTotal(source.actualSlices, weekRange);
    final rawCategoryMinutes = _categoryMinutes(source, weekRange);
    final categories = rankCategories(rawCategoryMinutes, source.categories);
    final notable = _notable(
      source: source,
      now: now,
      selectedWeekStart: weekStart,
    );
    return InsightsSnapshot(
      generatedFor: now,
      consistencyStart: consistencyStart,
      consistencyDays: visibleDays,
      streaks: streaks,
      weekStart: weekStart,
      weekEndExclusive: weekEnd,
      plannedMinutes: weekPlanned.planned,
      actualMinutes: weekActual,
      completedPlannedMinutes: weekPlanned.completed,
      categories: categories,
      notable: notable.take(2).toList(growable: false),
    );
  }

  static StreakSummary calculateStreaks(Iterable<ConsistencyDay> days) {
    final ordered = days.where((day) => !day.isFuture).toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    var current = 0;
    var best = 0;
    for (final day in ordered) {
      if (day.isNeutral) continue;
      if (day.isSuccessful) {
        current++;
        best = math.max(best, current);
      } else {
        current = 0;
      }
    }
    return StreakSummary(current: current, best: best);
  }

  static List<CategoryTime> rankCategories(
    Map<String?, int> minutesByCategory,
    List<Category> categories,
  ) {
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    final named = <CategoryTime>[];
    var uncategorized = 0;
    for (final entry in minutesByCategory.entries) {
      if (entry.value <= 0) continue;
      final category = entry.key == null ? null : categoryById[entry.key];
      if (category == null) {
        uncategorized += entry.value;
      } else {
        named.add(
          CategoryTime(
            id: category.id,
            name: category.name,
            colorHex: category.colorHex,
            actualMinutes: entry.value,
          ),
        );
      }
    }
    named.sort(_categorySort);
    final result = <CategoryTime>[...named.take(4)];
    if (named.length > 4) {
      result.add(
        CategoryTime(
          id: '__other__',
          name: 'Other',
          colorHex: '#7C8494',
          actualMinutes: named
              .skip(4)
              .fold(0, (sum, category) => sum + category.actualMinutes),
        ),
      );
    }
    if (uncategorized > 0) {
      result.add(
        CategoryTime(
          id: '__uncategorized__',
          name: 'Uncategorized',
          colorHex: '#9AA0A6',
          actualMinutes: uncategorized,
        ),
      );
    }
    result.sort(_categorySort);
    return result;
  }

  static int _categorySort(CategoryTime left, CategoryTime right) {
    final duration = right.actualMinutes.compareTo(left.actualMinutes);
    return duration != 0
        ? duration
        : left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  static ({int planned, int completed}) _plannedTotals(
    Iterable<Task> tasks,
    InsightDateRange range,
  ) {
    var planned = 0;
    var completed = 0;
    for (final task in tasks) {
      final start = task.startTime;
      final end = task.endTime;
      if (start == null || end == null) continue;
      final overlapStart = start.isAfter(range.start) ? start : range.start;
      final overlapEnd = end.isBefore(range.endExclusive)
          ? end
          : range.endExclusive;
      if (!overlapEnd.isAfter(overlapStart)) continue;
      final minutes = overlapEnd.difference(overlapStart).inMinutes;
      planned += minutes;
      if (task.status == TaskStatus.completed) completed += minutes;
    }
    return (planned: planned, completed: completed);
  }

  static int _actualTotal(
    Iterable<ActualTimeSlice> slices,
    InsightDateRange range,
  ) => slices
      .where((slice) => range.contains(slice.date))
      .fold(0, (sum, slice) => sum + math.max(0, slice.minutes));

  static Map<String?, int> _categoryMinutes(
    InsightsSourceData source,
    InsightDateRange range,
  ) {
    final taskCategory = {
      for (final task in source.actualTasks) task.id: task.categoryId,
    };
    final result = <String?, int>{};
    for (final slice in source.actualSlices) {
      if (slice.minutes <= 0 || !range.contains(slice.date)) continue;
      final categoryId = taskCategory[slice.taskId];
      result[categoryId] = (result[categoryId] ?? 0) + slice.minutes;
    }
    return result;
  }

  static List<NotableInsight> _notable({
    required InsightsSourceData source,
    required DateTime now,
    required DateTime selectedWeekStart,
  }) {
    final today = startOfDay(now);
    final currentWeek = startOfWeek(today);
    final selectedIsCurrent = isSameDay(selectedWeekStart, currentWeek);
    final comparableDayCount = selectedIsCurrent
        ? PlannerTimeZone.toPlannerLocal(today).weekday
        : 7;
    InsightDateRange window(DateTime start) =>
        InsightDateRange(start, addDays(start, comparableDayCount));
    final selectedRange = window(selectedWeekStart);
    final selectedCategories = _categoryMinutes(source, selectedRange);

    final comparableRanges = <InsightDateRange>[];
    for (var offset = 1; offset <= 4; offset++) {
      final candidate = window(addDays(selectedWeekStart, -7 * offset));
      final planned = _plannedTotals(source.plannedTasks, candidate).planned;
      final actual = _actualTotal(source.actualSlices, candidate);
      if (planned > 0 || actual > 0) comparableRanges.add(candidate);
    }

    NotableInsight? categoryObservation;
    var strongestDifference = 0.0;
    if (comparableRanges.length >= 2) {
      final categoryById = {
        for (final category in source.categories) category.id: category,
      };
      final ids = <String?>{...selectedCategories.keys};
      for (final range in comparableRanges) {
        ids.addAll(_categoryMinutes(source, range).keys);
      }
      for (final id in ids) {
        final baselineTotal = comparableRanges.fold<int>(
          0,
          (sum, range) => sum + (_categoryMinutes(source, range)[id] ?? 0),
        );
        final baseline = baselineTotal / comparableRanges.length;
        if (baseline <= 0) continue;
        final current = (selectedCategories[id] ?? 0).toDouble();
        final difference = current - baseline;
        if (difference.abs() < 60 || difference.abs() / baseline < 0.30) {
          continue;
        }
        if (difference.abs() <= strongestDifference) continue;
        strongestDifference = difference.abs();
        final name = id == null
            ? 'Uncategorized'
            : (categoryById[id]?.name ?? 'Uncategorized');
        categoryObservation = NotableInsight(
          kind: NotableInsightKind.categoryChange,
          message:
              '$name was ${_durationPhrase(difference.abs().round())} '
              '${difference > 0 ? 'above' : 'below'} your recent average.',
        );
      }
    }

    NotableInsight? gapObservation;
    final previousRange = window(addDays(selectedWeekStart, -7));
    final currentPlanned = _plannedTotals(
      source.plannedTasks,
      selectedRange,
    ).planned;
    final previousPlanned = _plannedTotals(
      source.plannedTasks,
      previousRange,
    ).planned;
    if (currentPlanned > 0 && previousPlanned > 0) {
      final currentGap =
          (currentPlanned - _actualTotal(source.actualSlices, selectedRange))
              .abs();
      final previousGap =
          (previousPlanned - _actualTotal(source.actualSlices, previousRange))
              .abs();
      final change = currentGap - previousGap;
      if (previousGap > 0 &&
          change.abs() >= 60 &&
          change.abs() / previousGap >= 0.20) {
        gapObservation = NotableInsight(
          kind: NotableInsightKind.planningGap,
          message: change < 0
              ? 'Planned and actual time were closer than last week.'
              : 'The gap between planned and actual time was larger than last week.',
        );
      }
    }
    return [?categoryObservation, ?gapObservation];
  }

  static String _durationPhrase(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '${remainder}m';
    if (remainder == 0) return '${hours}h';
    return '${hours}h ${remainder}m';
  }
}
