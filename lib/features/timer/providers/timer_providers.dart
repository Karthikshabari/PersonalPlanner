import 'dart:async';

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
/// Built on [Stream.multi] so the underlying Timer is cancelled the moment
/// the last listener goes away (widget dispose / provider autoDispose).
final activeTimerElapsedProvider =
    StreamProvider.autoDispose.family<int, String>((ref, taskId) {
  final active = ref.watch(activeTimerProvider).value;
  if (active == null || active.session.taskId != taskId) {
    return const Stream<int>.empty();
  }
  var current =
      DateTime.now().difference(active.session.startedAt).inSeconds;
  if (current < 0) current = 0;
  return Stream<int>.multi((channel) {
    channel.add(current);
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      current++;
      channel.add(current);
    });
    channel.onCancel = () {
      timer.cancel();
    };
  });
});

/// `⏱ 01:23:45` label format for timers.
String formatTimerClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}
