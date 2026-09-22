import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/models/timer_session.dart';
import '../../settings/providers/notification_settings_providers.dart';
import '../../sync/providers/sync_providers.dart';
import '../data/timer_repository.dart';
import '../domain/notification_coordinator.dart';
import '../domain/timer_service.dart';

final timerRepositoryProvider = Provider<TimerRepository>((ref) {
  return TimerRepository(ref.watch(appDatabaseProvider));
});

final timerServiceProvider = Provider<TimerService>((ref) {
  return TimerService(ref.watch(appDatabaseProvider));
});

final plannerNotificationCoordinatorProvider =
    Provider<PlannerNotificationCoordinator>((ref) {
      return PlannerNotificationCoordinator(
        database: ref.watch(appDatabaseProvider),
        notifications: ref.watch(notificationServiceProvider),
        accountId: ref.watch(openAccountScopeProvider)?.storageId,
      );
    });

/// UI-only in-flight feedback. The persisted TimerService independently
/// serializes transitions, so this is not a second timer state source.
final timerActionBusyProvider = NotifierProvider.autoDispose
    .family<TimerActionBusyNotifier, bool, String>(TimerActionBusyNotifier.new);

class TimerActionBusyNotifier extends Notifier<bool> {
  TimerActionBusyNotifier(this.actionScope);

  final String actionScope;

  @override
  bool build() => false;

  bool get isBusy => ref.mounted && state;

  void setBusy(bool value) {
    if (ref.mounted) state = value;
  }
}

/// The globally running session (if any) with its task's title. Null while
/// idle.
final activeTimerProvider = StreamProvider.autoDispose<ActiveTimer?>((ref) {
  return ref.watch(timerRepositoryProvider).watchActiveTimer();
});

/// The caller's unfinished session for one task. Paused work remains visible
/// here so the editor can Resume or Stop the same logical session.
final unfinishedTimerForTaskProvider = StreamProvider.autoDispose
    .family<TimerSession?, String>((ref, taskId) {
      return ref.watch(timerRepositoryProvider).watchUnfinishedForTask(taskId);
    });

/// An ownerless imported/legacy session. It never becomes active merely by
/// appearing here; the controls require an explicit Recover action.
final recoverableTimerForTaskProvider = StreamProvider.autoDispose
    .family<TimerSession?, String>((ref, taskId) {
      return ref.watch(timerRepositoryProvider).watchRecoverableForTask(taskId);
    });

/// A session owned by another device. It is presentation-only on this
/// device; local actions must not pause, stop, or take it over.
final foreignTimerForTaskProvider = StreamProvider.autoDispose
    .family<TimerSession?, String>((ref, taskId) {
      return ref
          .watch(timerRepositoryProvider)
          .watchForeignUnfinishedForTask(taskId);
    });

/// The desktop overlay continues to expose a paused local session when there
/// is no running one; foreign/unclaimed sessions are intentionally excluded.
final latestPausedTimerProvider = StreamProvider.autoDispose<ActiveTimer?>(
  (ref) => ref.watch(timerRepositoryProvider).watchLatestPausedTimer(),
);

/// Elapsed seconds for [taskId]'s running session. Ticks once per second
/// (periodic stream per planner.md Chunk 6 #7) and only emits while [taskId]
/// actually owns the global active timer. The first value is derived from
/// the persisted running segment. Ticks only request a fresh calculation;
/// they never become a second elapsed-time source of truth.
///
/// Built on [Stream.multi] so the underlying Timer and lifecycle observer are
/// cancelled the moment the last listener goes away (widget dispose /
/// provider autoDispose).
final activeTimerElapsedProvider = StreamProvider.autoDispose
    .family<int, String>((ref, taskId) {
      final active = ref.watch(activeTimerProvider).value;
      if (active == null || active.session.taskId != taskId) {
        return const Stream<int>.empty();
      }
      return Stream<int>.multi((channel) {
        void emit() => channel.add(
          elapsedSecondsForSession(active.session, DateTime.now()),
        );

        emit();
        final timer = Timer.periodic(const Duration(seconds: 1), (_) {
          emit();
        });
        final observer = _TimerElapsedLifecycleObserver(onResumed: emit);
        WidgetsBinding.instance.addObserver(observer);
        channel.onCancel = () {
          timer.cancel();
          WidgetsBinding.instance.removeObserver(observer);
        };
      });
    });

/// Computes persisted elapsed time from the session clock. Negative values can
/// occur after a manual device-clock rollback; clamp them rather than showing
/// an invalid negative timer.
int elapsedSecondsSince(DateTime startedAt, DateTime now) {
  final elapsed = now.difference(startedAt).inSeconds;
  return elapsed < 0 ? 0 : elapsed;
}

int elapsedSecondsForSession(TimerSession session, DateTime now) {
  if (session.state != TimerSessionState.running ||
      session.runningSince == null) {
    return session.durationSec;
  }
  return (session.durationSec + elapsedSecondsSince(session.runningSince!, now))
      .clamp(0, 1 << 31)
      .toInt();
}

/// Session-scoped clock for paused controls and overlays. The provider keeps
/// the same no-tick-authority rule as the historic active-task provider.
final timerSessionElapsedProvider = StreamProvider.autoDispose
    .family<int, TimerSession>((ref, session) {
      return Stream<int>.multi((channel) {
        void emit() =>
            channel.add(elapsedSecondsForSession(session, DateTime.now()));
        emit();
        Timer? timer;
        if (session.state == TimerSessionState.running) {
          timer = Timer.periodic(const Duration(seconds: 1), (_) => emit());
        }
        final observer = _TimerElapsedLifecycleObserver(onResumed: emit);
        WidgetsBinding.instance.addObserver(observer);
        channel.onCancel = () {
          timer?.cancel();
          WidgetsBinding.instance.removeObserver(observer);
        };
      });
    });

class _TimerElapsedLifecycleObserver with WidgetsBindingObserver {
  _TimerElapsedLifecycleObserver({required this.onResumed});

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

/// `⏱ 01:23:45` label format for timers.
String formatTimerClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}
