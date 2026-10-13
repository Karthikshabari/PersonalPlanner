import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/models/enums/task_status.dart';
import '../../../core/models/experiment.dart';
import '../../../core/models/inbox_closure.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../experiments/domain/experiment_days.dart';
import '../../experiments/domain/experiment_progress.dart';
import 'inbox_history.dart';
import 'inbox_source.dart';
import 'inbox_status.dart';

part 'inbox_board.freezed.dart';

/// One session of an idea with everything a trail row shows.
@freezed
abstract class InboxSessionView with _$InboxSessionView {
  const factory InboxSessionView({
    required InboxSessionFacts facts,
    required InboxSessionStatus status,

    /// Planner date of the start (`yyyy-MM-dd`); empty without a start.
    required String date,

    /// The saved Review reason, if any.
    String? reason,

    /// The session is on a break day, where Review asks no reason.
    @Default(false) bool breakDay,

    /// Same rule as Review's "N without a reason" (`awaitsReason`) plus the
    /// break-day rule.
    @Default(false) bool needsReason,
  }) = _InboxSessionView;
}

/// One idea with its derived status and the numbers its row shows.
@freezed
abstract class InboxIdeaView with _$InboxIdeaView {
  const factory InboxIdeaView({
    required InboxItemFacts item,
    required InboxItemStatus status,

    /// Sessions, soonest first, deleted ones included (status dropped).
    @Default(<InboxSessionView>[]) List<InboxSessionView> sessions,

    /// The event that holds the idea closed now; null unless closed.
    InboxClosure? closure,

    /// The outcome chip: Finished or an Experiment chip (Done), Closed or Let
    /// go (Dropped).
    String? chip,

    /// The experiment named by the open closure, when it is an experiment.
    String? experimentId,

    /// True when the open closure names an experiment whose row is gone.
    @Default(false) bool experimentMissing,

    /// When the idea left Open (closure time, or its latest done end).
    DateTime? resolvedAt,

    /// Start of the soonest upcoming session.
    DateTime? nextStart,

    /// Start of the most recent missed session.
    DateTime? lastMissedStart,

    /// End of the most recent missed session; Left over is ordered by it.
    DateTime? lastMissedEnd,
    @Default(0) int upcomingCount,
    @Default(0) int needsReasonCount,
  }) = _InboxIdeaView;
}

/// How many sessions are waiting for a reason in Review.
@freezed
abstract class InboxReasonsMissing with _$InboxReasonsMissing {
  const factory InboxReasonsMissing({
    @Default(0) int count,

    /// The most recent planner date among them.
    String? latestDate,
  }) = _InboxReasonsMissing;
}

/// The Inbox screen's whole state. Ids in the section lists, views in [byId],
/// so a row that did not change compares equal.
@freezed
abstract class InboxBoard with _$InboxBoard {
  const factory InboxBoard({
    @Default(<String>[]) List<String> leftOver,
    @Default(<String>[]) List<String> ideas,
    @Default(<String>[]) List<String> comingUp,
    @Default(<String>[]) List<String> done,
    @Default(<String>[]) List<String> dropped,
    @Default(0) int openCount,
    @Default(0) int doneCount,
    @Default(0) int droppedCount,
    @Default(InboxReasonsMissing()) InboxReasonsMissing reasonsMissing,
    @Default(<String, InboxIdeaView>{}) Map<String, InboxIdeaView> byId,

    /// The next moment any status can change.
    required DateTime nextBoundary,
  }) = _InboxBoard;
}

/// The earliest moment after [now] when a status can change: a session of a
/// listed idea starting or ending, or the next planner midnight (so Today and
/// the Review line roll over).
DateTime nextInboxBoundary(InboxSource source, DateTime now) {
  final local = PlannerTimeZone.toPlannerLocal(now);
  // A plain UTC value, like every other instant on the board, so equality
  // does not depend on the DateTime subclass.
  var next = DateTime.fromMicrosecondsSinceEpoch(
    PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day + 1,
    ).microsecondsSinceEpoch,
    isUtc: true,
  );
  final itemIds = {for (final item in source.items) item.id};
  for (final session in source.sessions) {
    if (!itemIds.contains(session.itemId) ||
        session.deletedAt != null ||
        (session.status != TaskStatus.planned &&
            session.status != TaskStatus.inProgress)) {
      continue;
    }
    for (final moment in [session.start, session.end]) {
      if (moment != null && moment.isAfter(now) && moment.isBefore(next)) {
        next = moment;
      }
    }
  }
  return next;
}

/// Builds the board. Pure: no clock, no database. [breakDates] maps each break
/// date (`yyyy-MM-dd`) to its label.
InboxBoard buildInboxBoard(
  InboxSource source, {
  required DateTime now,
  required Map<String, String> breakDates,
}) {
  final sessionsByItem = <String, List<InboxSessionFacts>>{};
  for (final session in source.sessions) {
    (sessionsByItem[session.itemId] ??= []).add(session);
  }
  final today = isoDateString(now);

  final byId = <String, InboxIdeaView>{};
  var missingCount = 0;
  String? missingLatest;

  for (final item in source.items) {
    final sessions = [...?sessionsByItem[item.id]]
      ..sort((a, b) {
        final left = a.start;
        final right = b.start;
        if (left == null || right == null) {
          if (left == right) return a.id.compareTo(b.id);
          return left == null ? 1 : -1;
        }
        final byStart = left.compareTo(right);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final status = itemStatusOf(item, sessions, now);
    final reopenedAt = InboxHistory.lastReopenedAt(item.history);

    final views = <InboxSessionView>[];
    DateTime? nextStart;
    DateTime? lastMissedStart;
    DateTime? lastMissedEnd;
    DateTime? latestDoneEnd;
    var upcoming = 0;
    var needReason = 0;
    for (final session in sessions) {
      final sessionStatus = sessionStatusOf(session, now);
      final start = session.start;
      final date = start == null ? '' : isoDateString(start);
      final breakDay = date.isNotEmpty && breakDates.containsKey(date);
      final saved = source.reasons[session.id]?.trim();
      final reason = saved == null || saved.isEmpty ? null : saved;
      final needsReason =
          (sessionStatus == InboxSessionStatus.missed ||
              sessionStatus == InboxSessionStatus.carried ||
              sessionStatus == InboxSessionStatus.skipped) &&
          !session.end!.isAfter(now) &&
          !breakDay &&
          reason == null;
      views.add(
        InboxSessionView(
          facts: session,
          status: sessionStatus,
          date: date,
          reason: reason,
          breakDay: breakDay,
          needsReason: needsReason,
        ),
      );
      if (needsReason) {
        needReason++;
        missingCount++;
        if (missingLatest == null || date.compareTo(missingLatest) > 0) {
          missingLatest = date;
        }
      }
      switch (sessionStatus) {
        case InboxSessionStatus.upcoming:
          upcoming++;
          if (nextStart == null || start!.isBefore(nextStart)) {
            nextStart = start;
          }
        case InboxSessionStatus.missed:
          if (lastMissedEnd == null || session.end!.isAfter(lastMissedEnd)) {
            lastMissedEnd = session.end;
          }
          if (lastMissedStart == null || start!.isAfter(lastMissedStart)) {
            lastMissedStart = start;
          }
        case InboxSessionStatus.done:
          if (reopenedAt == null || session.createdAt.isAfter(reopenedAt)) {
            final end = session.end!;
            if (latestDoneEnd == null || end.isAfter(latestDoneEnd)) {
              latestDoneEnd = end;
            }
          }
        case InboxSessionStatus.carried:
        case InboxSessionStatus.skipped:
        case InboxSessionStatus.dropped:
          break;
      }
    }

    final closure = InboxHistory.openClosure(item.history);
    final experimentId = closure?.kind == InboxCloseKind.experiment
        ? closure!.experimentId
        : null;
    final experiment = experimentId == null
        ? null
        : source.experiments[experimentId];
    final experimentMissing =
        experimentId != null &&
        (experiment == null || experiment.deletedAt != null);
    String? chip;
    DateTime? resolvedAt;
    if (status == InboxItemStatus.closed) {
      resolvedAt = closure!.at;
      chip = switch (closure.kind) {
        InboxCloseKind.closed => 'Closed',
        InboxCloseKind.letGo => 'Let go',
        InboxCloseKind.experiment => _experimentChip(
          experimentMissing ? null : experiment,
          today,
        ),
      };
    } else if (status == InboxItemStatus.finished) {
      resolvedAt = latestDoneEnd;
      chip = 'Finished';
    }

    byId[item.id] = InboxIdeaView(
      item: item,
      status: status,
      sessions: views,
      closure: closure,
      chip: chip,
      experimentId: experimentId,
      experimentMissing: experimentMissing,
      resolvedAt: resolvedAt,
      nextStart: nextStart,
      lastMissedStart: lastMissedStart,
      lastMissedEnd: lastMissedEnd,
      upcomingCount: upcoming,
      needsReasonCount: needReason,
    );
  }

  List<String> idsWhere(InboxItemStatus status) => [
    for (final view in byId.values)
      if (view.status == status) view.item.id,
  ];

  final leftOver = idsWhere(InboxItemStatus.left)
    ..sort(
      (a, b) =>
          _compareDesc(byId[a]!.lastMissedEnd, byId[b]!.lastMissedEnd, a, b),
    );
  final ideas = idsWhere(InboxItemStatus.idea)
    ..sort(
      (a, b) =>
          _compareDesc(byId[a]!.item.createdAt, byId[b]!.item.createdAt, a, b),
    );
  final comingUp = idsWhere(InboxItemStatus.soon)
    ..sort((a, b) {
      final byStart = byId[a]!.nextStart!.compareTo(byId[b]!.nextStart!);
      return byStart != 0 ? byStart : a.compareTo(b);
    });
  // One rule per idea: a finished idea and an experiment closure are Done; a
  // closed or let-go closure is Dropped. Both are newest resolution first.
  bool isDropped(String id) {
    final kind = byId[id]!.closure?.kind;
    return kind == InboxCloseKind.closed || kind == InboxCloseKind.letGo;
  }

  int byResolved(String a, String b) =>
      _compareDesc(byId[a]!.resolvedAt, byId[b]!.resolvedAt, a, b);
  final resolved = [
    ...idsWhere(InboxItemStatus.closed),
    ...idsWhere(InboxItemStatus.finished),
  ];
  final done = [
    for (final id in resolved)
      if (!isDropped(id)) id,
  ]..sort(byResolved);
  final dropped = [
    for (final id in resolved)
      if (isDropped(id)) id,
  ]..sort(byResolved);

  return InboxBoard(
    leftOver: leftOver,
    ideas: ideas,
    comingUp: comingUp,
    done: done,
    dropped: dropped,
    openCount: leftOver.length + ideas.length + comingUp.length,
    doneCount: done.length,
    droppedCount: dropped.length,
    reasonsMissing: InboxReasonsMissing(
      count: missingCount,
      latestDate: missingLatest,
    ),
    byId: byId,
    nextBoundary: nextInboxBoundary(source, now),
  );
}

/// Newest first; a missing instant sorts last; the id breaks ties.
int _compareDesc(DateTime? a, DateTime? b, String idA, String idB) {
  if (a == null || b == null) {
    if (a == b) return idA.compareTo(idB);
    return a == null ? 1 : -1;
  }
  final byTime = b.compareTo(a);
  return byTime != 0 ? byTime : idA.compareTo(idB);
}

/// "Experiment · Day 3 of 30", "Experiment · Concluded Oct 9",
/// "Experiment · Kept" or "Experiment · Removed" (a missing record).
String _experimentChip(InboxExperimentFacts? facts, String today) {
  if (facts == null) return 'Experiment · Removed';
  final experiment = Experiment(
    id: facts.id,
    tagId: '',
    tagName: facts.name,
    startDate: facts.startDate,
    endDate: facts.endDate,
    weekdayTargetMin: 0,
    weekendTargetMin: 0,
    checkInEveryDays: 1,
    status: facts.status,
    outcome: facts.outcome,
    concludedOn: facts.concludedOn,
    retiredAt: facts.retiredAt,
    createdAt: DateTime.utc(1970),
    updatedAt: DateTime.utc(1970),
  );
  if (experiment.isKept) return 'Experiment · Kept';
  final label = experimentStatusLabel(
    experiment,
    calendarDaysBetween(facts.startDate, facts.endDate) + 1,
    today,
  );
  const running = 'Running · ';
  return 'Experiment · ${label.startsWith(running) ? label.substring(running.length) : label}';
}
