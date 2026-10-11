import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/category.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/models/task.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planned_clock_time.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../day_context/data/day_context_repository.dart';
import '../../day_context/domain/break_day.dart';
import '../../timeline/data/task_repository.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import 'analytics_models.dart';

/// Loads Insights from local history in bounded range passes. There is no
/// per-calendar-day database query: day slicing and grouping happen in memory.
class InsightsService {
  InsightsService(this._db);

  static final _placeholderInstant = DateTime.utc(2000);

  final AppDatabase _db;

  Future<InsightsSnapshot> compute({
    required DateTime weekStart,
    DateTime? now,
    double followThroughTarget = defaultFollowThroughTarget,
    BreakDayRule? breakDays,
    // Retained for source compatibility with older callers. The consistency
    // history is now always the rolling year on every form factor.
    int desktopMonthCount = 12,
  }) async {
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
    // Actual extends to the end of the selected week so its total matches the
    // Weekly Review, which counts a manual Actual on a later day of the week.
    // Calendar days and elapsed-weekday comparisons still stop at today.
    final selectedWeekEnd = addDays(selectedWeek, 7);
    final actualRangeEnd = selectedWeekEnd.isAfter(addDays(today, 1))
        ? selectedWeekEnd
        : addDays(today, 1);
    final currentWeekEnd = addDays(currentWeekStart, 7);
    final plannedRangeEnd = currentWeekEnd.isAfter(consistencyEnd)
        ? currentWeekEnd
        : consistencyEnd;

    // One planned-history query supports the visible calendar plus accurate
    // all-history current/best streaks. It retains the DAO's canonical active,
    // scheduled, interval-overlap predicate.
    //
    // The calculator only adds up planned minutes, so each task is reduced to
    // its start, end and status (the typed full-row read of the whole history
    // cost about 100 ms; this costs about 15 ms). The other fields stay empty.
    final plannedSpans = await _db.taskDao.getScheduleSpansBetween(
      PlannerTimeZone.calendarDate(2000, 1, 1),
      plannedRangeEnd,
    );
    final plannedTasks = [
      for (final span in plannedSpans)
        Task(
          id: '',
          title: '',
          startTime: span.start,
          endTime: span.end,
          status: TaskStatus.fromDb(span.status),
          createdAt: _placeholderInstant,
          updatedAt: _placeholderInstant,
        ),
    ];

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

    // Same task set as DailyStatsService: every task starting in range,
    // including soft-deleted ones, so their manual Actual is not dropped.
    final startsInRange = [
      Variable<String>(actualRangeStart.toUtc().toIso8601String()),
      Variable<String>(actualRangeEnd.toUtc().toIso8601String()),
    ];
    final tasksStartingInRange = [
      for (final row
          in await _db
              .customSelect(
                'SELECT id FROM tasks WHERE start_time >= ? AND start_time < ?',
                variables: startsInRange,
                readsFrom: {_db.tasks},
              )
              .get())
        row.read<String>('id'),
    ];
    final actualTaskIds = <String>{
      ...tasksStartingInRange,
      for (final session in overlappingSessions) session.taskId,
    };
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
    // `allocateActualByDate` yields nothing for a task without finished timer
    // history and without a manually recorded Actual, so only those tasks need
    // their row loaded. A manual-only task can only be in range by its start.
    final manualOnlyIds = actualTaskIds.isEmpty
        ? const <String>[]
        : [
            for (final row
                in await _db
                    .customSelect(
                      'SELECT id FROM tasks WHERE manual_actual_set = 1 '
                      'AND start_time >= ? AND start_time < ?',
                      variables: startsInRange,
                      readsFrom: {_db.tasks},
                    )
                    .get())
              row.read<String>('id'),
          ];
    final producerIds = <String>{...historyByTask.keys, ...manualOnlyIds};
    final actualRows = producerIds.isEmpty
        ? const <TaskRow>[]
        : await (_db.select(
            _db.tasks,
          )..where((task) => task.id.isIn(producerIds))).get();
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
      followThroughTarget: followThroughTarget,
      breakDays: breakDays,
    );
  }
}

/// Pure duration-weighted Insights formulas, independent of Flutter and SQL.
abstract final class InsightsCalculator {
  static InsightsSnapshot calculate({
    required InsightsSourceData source,
    required DateTime now,
    required DateTime selectedWeekStart,
    required DateTime consistencyStart,
    double followThroughTarget = defaultFollowThroughTarget,
    BreakDayRule? breakDays,
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
    // Break days count in nothing: no streak step, no week total, no average.
    final breakDates = (breakDays ?? BreakDayRule.defaults).breakDates(
      source.dayContexts,
    );
    final dates = <DateTime>[];
    for (
      var date = historyStart;
      date.isBefore(consistencyEnd);
      date = addDays(date, 1)
    ) {
      dates.add(date);
    }
    final plannedByDay = _plannedTotalsByDay(source.plannedTasks, dates);
    final allDays = <ConsistencyDay>[];
    for (var index = 0; index < dates.length; index++) {
      final date = dates[index];
      allDays.add(
        ConsistencyDay(
          date: date,
          plannedMinutes: plannedByDay.planned[index],
          completedPlannedMinutes: plannedByDay.completed[index],
          actualMinutes: actualByDate[isoDateString(date)] ?? 0,
          breakLabel: breakDates[isoDateString(date)],
          isFuture: date.isAfter(today),
          isToday: isSameDay(date, today),
        ),
      );
    }
    final visibleDays = allDays
        .where((day) => !day.date.isBefore(consistencyStart))
        .toList(growable: false);
    final streaks = calculateStreaks(allDays, target: followThroughTarget);
    final weekRange = InsightDateRange(weekStart, weekEnd);
    final weekPlanned = _plannedTotals(
      source.plannedTasks,
      weekRange,
      breakDates,
    );
    final weekActual = _actualTotal(source.actualSlices, weekRange, breakDates);
    final rawCategoryMinutes = _categoryMinutes(source, weekRange, breakDates);
    final categories = rankCategories(rawCategoryMinutes, source.categories);
    final notable = _notable(
      source: source,
      now: now,
      selectedWeekStart: weekStart,
      breakDates: breakDates,
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
      followThroughTarget: followThroughTarget,
    );
  }

  /// Success adds one, Missed resets to zero, Started, Empty and Break keep
  /// the streak as it is. Today counts only once it is a Success ([classifyDay]).
  static StreakSummary calculateStreaks(
    Iterable<ConsistencyDay> days, {
    double target = defaultFollowThroughTarget,
  }) {
    final ordered = days.where((day) => !day.isFuture).toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    var current = 0;
    var best = 0;
    for (final day in ordered) {
      switch (classifyDay(day, target: target)) {
        case DayResult.success:
          current++;
          best = math.max(best, current);
        case DayResult.missed:
          current = 0;
        case DayResult.started || DayResult.empty || DayResult.breakDay || null:
          break;
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

  /// [_plannedTotals] for every one-day range `[date, date + 1)` of [dates]
  /// (ascending planner days) in a single pass over [tasks]: each task adds
  /// its clipped interval to the days it touches, then each day takes the
  /// union. Looping every day over every task cost O(days x tasks) (about 4
  /// million overlap tests for two years of history).
  static ({List<int> planned, List<int> completed}) _plannedTotalsByDay(
    Iterable<Task> tasks,
    List<DateTime> dates,
  ) {
    final ranges = [
      for (final date in dates) InsightDateRange(date, addDays(date, 1)),
    ];
    final plannedSpans = List.generate(dates.length, (_) => <PlannedSpan>[]);
    final completedSpans = List.generate(dates.length, (_) => <PlannedSpan>[]);
    for (final task in tasks) {
      final start = task.startTime;
      final end = task.endTime;
      if (start == null || end == null) continue;
      // First day whose range ends after the task starts (ranges ascend).
      var low = 0;
      var high = ranges.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (ranges[middle].endExclusive.isAfter(start)) {
          high = middle;
        } else {
          low = middle + 1;
        }
      }
      for (var index = low; index < ranges.length; index++) {
        if (!ranges[index].start.isBefore(end)) break;
        final span = (start: start, end: end);
        plannedSpans[index].add(span);
        if (task.status == TaskStatus.completed) {
          completedSpans[index].add(span);
        }
      }
    }
    final planned = List<int>.filled(dates.length, 0);
    final completed = List<int>.filled(dates.length, 0);
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      if (plannedSpans[index].isEmpty) continue;
      planned[index] = PlannedClockTime.unionMinutes(
        plannedSpans[index],
        range.start,
        range.endExclusive,
      );
      completed[index] = PlannedClockTime.unionMinutes(
        completedSpans[index],
        range.start,
        range.endExclusive,
      );
    }
    return (planned: planned, completed: completed);
  }

  /// Clock time of [range] without its break days: per day, the union of the
  /// planned blocks and the union of the completed ones (so completed never
  /// exceeds planned). The day unions add up to the range's union.
  static ({int planned, int completed}) _plannedTotals(
    Iterable<Task> tasks,
    InsightDateRange range,
    Map<String, String> breakDates,
  ) {
    final days = [
      for (
        var day = range.start;
        day.isBefore(range.endExclusive);
        day = addDays(day, 1)
      )
        day,
    ];
    if (!days.any((day) => breakDates.containsKey(isoDateString(day)))) {
      return _clockTotals(tasks, range);
    }
    final overlapping = [
      for (final task in tasks)
        if (task.startTime != null &&
            task.endTime != null &&
            task.startTime!.isBefore(range.endExclusive) &&
            task.endTime!.isAfter(range.start))
          task,
    ];
    var planned = 0;
    var completed = 0;
    for (final day in days) {
      if (breakDates.containsKey(isoDateString(day))) continue;
      final totals = _clockTotals(
        overlapping,
        InsightDateRange(day, addDays(day, 1)),
      );
      planned += totals.planned;
      completed += totals.completed;
    }
    return (planned: planned, completed: completed);
  }

  static ({int planned, int completed}) _clockTotals(
    Iterable<Task> tasks,
    InsightDateRange range,
  ) {
    final planned = <PlannedSpan>[];
    final completed = <PlannedSpan>[];
    for (final task in tasks) {
      final start = task.startTime;
      final end = task.endTime;
      if (start == null || end == null) continue;
      final span = (start: start, end: end);
      planned.add(span);
      if (task.status == TaskStatus.completed) completed.add(span);
    }
    return (
      planned: PlannedClockTime.unionMinutes(
        planned,
        range.start,
        range.endExclusive,
      ),
      completed: PlannedClockTime.unionMinutes(
        completed,
        range.start,
        range.endExclusive,
      ),
    );
  }

  static int _actualTotal(
    Iterable<ActualTimeSlice> slices,
    InsightDateRange range,
    Map<String, String> breakDates,
  ) => slices
      .where(
        (slice) =>
            range.contains(slice.date) &&
            !breakDates.containsKey(isoDateString(slice.date)),
      )
      .fold(0, (sum, slice) => sum + math.max(0, slice.minutes));

  static Map<String?, int> _categoryMinutes(
    InsightsSourceData source,
    InsightDateRange range,
    Map<String, String> breakDates,
  ) {
    final taskCategory = {
      for (final task in source.actualTasks) task.id: task.categoryId,
    };
    final result = <String?, int>{};
    for (final slice in source.actualSlices) {
      if (slice.minutes <= 0 ||
          !range.contains(slice.date) ||
          breakDates.containsKey(isoDateString(slice.date))) {
        continue;
      }
      final categoryId = taskCategory[slice.taskId];
      result[categoryId] = (result[categoryId] ?? 0) + slice.minutes;
    }
    return result;
  }

  static List<NotableInsight> _notable({
    required InsightsSourceData source,
    required DateTime now,
    required DateTime selectedWeekStart,
    required Map<String, String> breakDates,
  }) {
    final today = startOfDay(now);
    final currentWeek = startOfWeek(today);
    final selectedIsCurrent = isSameDay(selectedWeekStart, currentWeek);
    final comparableDayCount = selectedIsCurrent ? dayOfPlannerWeek(today) : 7;
    InsightDateRange window(DateTime start) =>
        InsightDateRange(start, addDays(start, comparableDayCount));
    final selectedRange = window(selectedWeekStart);
    final selectedCategories = _categoryMinutes(
      source,
      selectedRange,
      breakDates,
    );

    final comparableRanges = <InsightDateRange>[];
    for (var offset = 1; offset <= 4; offset++) {
      final candidate = window(addDays(selectedWeekStart, -7 * offset));
      final planned = _plannedTotals(
        source.plannedTasks,
        candidate,
        breakDates,
      ).planned;
      final actual = _actualTotal(source.actualSlices, candidate, breakDates);
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
        ids.addAll(_categoryMinutes(source, range, breakDates).keys);
      }
      for (final id in ids) {
        final baselineTotal = comparableRanges.fold<int>(
          0,
          (sum, range) =>
              sum + (_categoryMinutes(source, range, breakDates)[id] ?? 0),
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
      breakDates,
    ).planned;
    final previousPlanned = _plannedTotals(
      source.plannedTasks,
      previousRange,
      breakDates,
    ).planned;
    if (currentPlanned > 0 && previousPlanned > 0) {
      final currentGap =
          (currentPlanned -
                  _actualTotal(source.actualSlices, selectedRange, breakDates))
              .abs();
      final previousGap =
          (previousPlanned -
                  _actualTotal(source.actualSlices, previousRange, breakDates))
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
