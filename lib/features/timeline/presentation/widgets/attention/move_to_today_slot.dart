import '../../../../../core/models/task.dart';
import '../../../../../core/utils/date_utils.dart';
import '../../../../../core/utils/planner_time_zone.dart';
import '../../../domain/conflict_resolver.dart';
import '../../../domain/snap_to_grid.dart' show minutesPerDay;

/// A start and end for a task moved to today.
typedef TodaySlot = ({DateTime start, DateTime end});

/// Used when a task has no planned interval to keep.
const _fallbackDurationMinutes = 60;

/// "Move to today" needs a time. The rule (decision D3):
///
/// * the same planner-local clock time today, when that is still at least 15
///   minutes after [now] and the task still ends today (overlaps are left to
///   the existing conflict dialog);
/// * otherwise the first free grid slot at or after [now] that fits the
///   task's duration, free of [todaysTasks];
/// * null when nothing fits before midnight.
///
/// Presentation helper only: nothing is persisted here.
TodaySlot? moveToTodaySlot(
  Task task,
  DateTime now,
  int gridMinutes,
  List<Task> todaysTasks,
) {
  final duration = _durationMinutes(task);
  final nowMinutes = _minutesFromMidnightCeil(now);

  final originalStart = task.startTime;
  if (originalStart != null) {
    final sameTime = minutesSinceMidnight(originalStart);
    if (sameTime >= nowMinutes + 15 && sameTime + duration <= minutesPerDay) {
      return _slotAt(now, sameTime, duration);
    }
  }

  final slot = ConflictResolver.findNextAvailableSlot(
    durationMinutes: duration,
    dayTasks: todaysTasks,
    searchFromMinutes: _ceilToGrid(nowMinutes, gridMinutes),
    day: now,
  );
  return slot == null ? null : _slotAt(now, slot, duration);
}

/// One task of a bulk move and where it goes.
typedef PlacedMove = ({Task task, TodaySlot slot});

/// Places [tasks] (oldest first) one after another from [now]: each at the
/// first free grid slot after the previous one, durations kept. Stops at the
/// first task that no longer fits before midnight; the returned list holds
/// the tasks that do fit, so `result.length` is how many fit.
List<PlacedMove> placeAllToday(
  List<Task> tasks,
  DateTime now,
  int gridMinutes,
  List<Task> todaysTasks,
) {
  final placed = <PlacedMove>[];
  var cursor = _ceilToGrid(_minutesFromMidnightCeil(now), gridMinutes);
  for (final task in tasks) {
    final duration = _durationMinutes(task);
    final slot = ConflictResolver.findNextAvailableSlot(
      durationMinutes: duration,
      dayTasks: todaysTasks,
      searchFromMinutes: cursor,
      day: now,
    );
    if (slot == null) break;
    placed.add((task: task, slot: _slotAt(now, slot, duration)));
    cursor = _ceilToGrid(slot + duration, gridMinutes);
  }
  return placed;
}

int _durationMinutes(Task task) {
  final minutes = task.scheduledDuration?.inMinutes ?? 0;
  return minutes > 0 ? minutes : _fallbackDurationMinutes;
}

/// Minutes since planner midnight, rounded up so a slot is never in the past.
int _minutesFromMidnightCeil(DateTime instant) {
  final local = PlannerTimeZone.toPlannerLocal(instant);
  final minutes = local.hour * 60 + local.minute;
  final partial =
      local.second > 0 || local.millisecond > 0 || local.microsecond > 0;
  return partial ? minutes + 1 : minutes;
}

int _ceilToGrid(int minutes, int grid) =>
    grid <= 0 ? minutes : ((minutes + grid - 1) ~/ grid) * grid;

TodaySlot _slotAt(DateTime now, int minuteOfDay, int durationMinutes) {
  final local = PlannerTimeZone.toPlannerLocal(now);
  final start = PlannerTimeZone.calendarDate(
    local.year,
    local.month,
    local.day,
    minute: minuteOfDay,
  );
  return (start: start, end: start.add(Duration(minutes: durationMinutes)));
}
