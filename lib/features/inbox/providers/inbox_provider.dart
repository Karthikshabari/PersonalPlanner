import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/models/inbox_item.dart';
import '../../../core/providers/reactive_stats_stream.dart';
import '../../day_context/providers/day_context_presets_provider.dart';
import '../data/inbox_repository.dart';
import '../domain/inbox_board.dart';
import '../domain/inbox_dates.dart';
import '../domain/inbox_source.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/planner_time_zone.dart';

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepository(ref.watch(appDatabaseProvider));
});

typedef MinuteClockFactory = Stream<DateTime> Function();

final minuteClockProvider = Provider<MinuteClockFactory>((ref) {
  return _minuteClock;
});

/// Inbox list: explicit inbox items + overdue surfaced tasks. On first
/// listen, stamps `missed_at` on newly detected overdue rows.
final inboxClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return ref.watch(minuteClockProvider)();
});

Stream<DateTime> _minuteClock() {
  return Stream<DateTime>.multi((controller) {
    var stopped = false;
    Timer? first;
    Timer? repeating;

    void emitNow() {
      if (!stopped) controller.add(DateTime.now());
    }

    emitNow();
    final now = DateTime.now();
    final local = PlannerTimeZone.toPlannerLocal(now);
    final nextMinute = PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day,
      hour: local.hour,
      minute: local.minute + 1,
    );
    first = Timer(nextMinute.difference(now), () {
      emitNow();
      repeating = Timer.periodic(const Duration(minutes: 1), (_) => emitNow());
    });
    controller.onCancel = () {
      stopped = true;
      first?.cancel();
      repeating?.cancel();
    };
  });
}

final overdueStampProvider = FutureProvider.autoDispose.family<int, DateTime>((
  ref,
  asOf,
) {
  return ref.watch(inboxRepositoryProvider).stampOverdue(asOf);
});

final inboxProvider = StreamProvider.autoDispose<List<InboxItem>>((ref) {
  final repo = ref.watch(inboxRepositoryProvider);
  final clock = ref.watch(inboxClockProvider);
  if (clock.hasError) {
    return Stream<List<InboxItem>>.error(clock.error!, clock.stackTrace);
  }
  if (!clock.hasValue) return const Stream<List<InboxItem>>.empty();
  final asOf = clock.requireValue;
  final stamp = ref.watch(overdueStampProvider(asOf));
  if (stamp.hasError) {
    return Stream<List<InboxItem>>.error(stamp.error!, stamp.stackTrace);
  }
  // A block on a break day is never shown as missed; it stays on the
  // timeline and can still be completed.
  final breakDates = ref.watch(breakDatesProvider);
  if (breakDates.hasError) {
    return Stream<List<InboxItem>>.error(
      breakDates.error!,
      breakDates.stackTrace,
    );
  }
  if (!breakDates.hasValue) return const Stream<List<InboxItem>>.empty();
  final dates = breakDates.requireValue;
  final items = repo.watchInboxItems(asOf);
  if (dates.isEmpty) return items;
  return items.map(
    (list) => [
      for (final item in list)
        if (!(item.isOverdue &&
            item.task.startTime != null &&
            dates.containsKey(isoDateString(item.task.startTime!))))
          item,
    ],
  );
});

/// Small Day-surface projection: only overdue scheduled work and explicit
/// Inbox captures whose date-only due date is today. General captures remain
/// available from the dedicated Inbox screen.
final dayAttentionProvider = StreamProvider.autoDispose<List<InboxItem>>((ref) {
  final clock = ref.watch(inboxClockProvider);
  final inbox = ref.watch(inboxProvider);
  if (clock.hasError) {
    return Stream<List<InboxItem>>.error(clock.error!, clock.stackTrace);
  }
  if (inbox.hasError) {
    return Stream<List<InboxItem>>.error(inbox.error!, inbox.stackTrace);
  }
  if (!clock.hasValue || !inbox.hasValue) {
    return const Stream<List<InboxItem>>.empty();
  }
  final today = isoDateString(clock.requireValue);
  return Stream.value(
    inbox.requireValue
        .where((item) => item.isOverdue || item.task.dueDate == today)
        .toList(growable: false),
  );
});

/// Date-only comparison against the application's canonical Monday–Sunday
/// week containing planner-local today.
bool isInboxItemVisibleInToday(InboxItem item, DateTime now) {
  final dueDate = item.task.dueDate;
  if (dueDate == null) return true;
  final weekStart = startOfWeek(PlannerTimeZone.toPlannerLocal(now));
  final weekEnd = addDays(weekStart, 7);
  final due = parseIsoDate(dueDate);
  return !due.isBefore(weekStart) && due.isBefore(weekEnd);
}

// ---------------------------------------------------------------------------
// The new Inbox board. The providers above stay for Day's Needs-attention
// panel; these are auto-dispose, so nothing runs while the screen is closed.
// ---------------------------------------------------------------------------

/// The clock the Inbox board reads. Overridable in tests.
final inboxNowFactoryProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Ideas, sessions, saved Review reasons and experiments, re-read when one of
/// the tables behind them changes. An unchanged result is not emitted.
final inboxSourceProvider = StreamProvider.autoDispose<InboxSource>((ref) {
  final repo = ref.watch(inboxRepositoryProvider);
  return watchReactiveStats<InboxSource>(
    repo.database,
    repo.readSource,
    tables: [
      repo.database.tasks,
      repo.database.dailyReviews,
      repo.database.experiments,
      repo.database.tags,
    ],
    isSame: (a, b) => a == b,
  );
});

/// "Now" for the Inbox board. One one-shot timer fires at the next moment any
/// status can change (a session starting or ending, or planner midnight) and
/// is re-armed each time; an app-resume check catches a timer that did not run
/// while the app was in the background. Alive only while the board is watched.
final inboxScreenClockProvider =
    NotifierProvider.autoDispose<InboxScreenClock, DateTime>(
      InboxScreenClock.new,
    );

class InboxScreenClock extends Notifier<DateTime> {
  Timer? _timer;
  late final _ResumeObserver _observer = _ResumeObserver(_refresh);

  @override
  DateTime build() {
    final nowFactory = ref.read(inboxNowFactoryProvider);
    final now = nowFactory();
    // A write that adds or moves a session changes the next boundary.
    ref.listen(inboxSourceProvider, (_, _) => _arm());
    WidgetsBinding.instance.addObserver(_observer);
    ref.onDispose(() {
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(_observer);
    });
    _arm(now);
    return now;
  }

  void _refresh() {
    state = ref.read(inboxNowFactoryProvider)();
    _arm(state);
  }

  void _arm([DateTime? from]) {
    _timer?.cancel();
    final now = from ?? ref.read(inboxNowFactoryProvider)();
    final source = ref.read(inboxSourceProvider).value;
    final boundary = source == null ? null : nextInboxBoundary(source, now);
    if (boundary == null) return;
    final delay = boundary.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      // Move past the boundary even if the timer fired a few ms early.
      final fired = ref.read(inboxNowFactoryProvider)();
      state = fired.isBefore(boundary) ? boundary : fired;
      _arm(state);
    });
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

/// The board: sections, counts, the Review line and the next boundary.
final inboxBoardProvider = Provider.autoDispose<AsyncValue<InboxBoard>>((ref) {
  final source = ref.watch(inboxSourceProvider);
  final breakDates = ref.watch(breakDatesProvider);
  final now = ref.watch(inboxScreenClockProvider);
  if (source.hasError) {
    return AsyncError(source.error!, source.stackTrace ?? StackTrace.empty);
  }
  if (breakDates.hasError) {
    return AsyncError(
      breakDates.error!,
      breakDates.stackTrace ?? StackTrace.empty,
    );
  }
  final sourceValue = source.value;
  final breakValue = breakDates.value;
  if (sourceValue == null || breakValue == null) {
    return const AsyncLoading<InboxBoard>();
  }
  return AsyncData(
    buildInboxBoard(sourceValue, now: now, breakDates: breakValue),
  );
});

/// The idea whose trail is open; only one at a time.
final inboxExpandedItemProvider = StateProvider<String?>((ref) => null);

/// The unsaved picks of an idea's dates panel, by idea id. Kept here so that
/// opening another idea does not lose them; cleared by Save and Cancel, and
/// gone on restart.
final inboxDatesDraftProvider = StateProvider.family<InboxDatesDraft?, String>(
  (ref, id) => null,
);

/// Set by Search to open the Inbox with this idea expanded.
final inboxFocusItemProvider = StateProvider<String?>((ref) => null);

/// Text typed into the Inbox capture box and not yet added. Kept here, not in
/// the field, because switching tabs rebuilds the page (flat ShellRoute).
final inboxCaptureDraftProvider = StateProvider<String>((ref) => '');
