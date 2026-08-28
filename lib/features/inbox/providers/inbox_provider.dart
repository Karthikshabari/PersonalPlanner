import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/inbox_item.dart';
import '../data/inbox_repository.dart';
import '../../../core/providers/database_provider.dart';

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
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
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

final overdueStampProvider = FutureProvider.autoDispose
    .family<int, DateTime>((ref, asOf) {
  return ref.watch(inboxRepositoryProvider).stampOverdue(asOf);
});

final inboxProvider = StreamProvider.autoDispose<List<InboxItem>>((ref) {
  final repo = ref.watch(inboxRepositoryProvider);
  final asOf = ref.watch(inboxClockProvider).value ?? DateTime.now();
  final stamp = ref.watch(overdueStampProvider(asOf));
  if (stamp.hasError) {
    return Stream<List<InboxItem>>.error(stamp.error!, stamp.stackTrace);
  }
  return repo.watchInboxItems(asOf);
});
