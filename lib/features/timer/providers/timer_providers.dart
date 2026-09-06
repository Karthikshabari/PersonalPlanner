import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../data/timer_repository.dart';
import '../domain/timer_service.dart';

final timerRepositoryProvider = Provider<TimerRepository>((ref) {
  return TimerRepository(ref.watch(appDatabaseProvider));
});

final timerServiceProvider = Provider<TimerService>((ref) {
  return TimerService(ref.watch(appDatabaseProvider));
});

/// The globally running session (if any) with its task's title. Null while
/// idle.
final activeTimerProvider = StreamProvider.autoDispose<ActiveTimer?>((ref) {
  return ref.watch(timerRepositoryProvider).watchActiveTimer();
});

/// Elapsed seconds for [taskId]'s running session. Ticks once per second
/// (periodic stream per planner.md Chunk 6 #7) and only emits while [taskId]
/// actually owns the global active timer. The first value is derived from
/// the session's start time; each tick adds one second so the display also
/// advances deterministically under the test clock.
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
        var tickSeconds = 0;
        void emit() => channel.add(
          elapsedSecondsSince(
            active.session.startedAt,
            DateTime.now(),
          ).clamp(tickSeconds, 1 << 31).toInt(),
        );

        emit();
        final timer = Timer.periodic(const Duration(seconds: 1), (_) {
          tickSeconds++;
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
