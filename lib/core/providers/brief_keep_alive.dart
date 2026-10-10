import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// How long a date-keyed stream outlives its last listener, so stepping back
/// to a day or week just left (or ahead to one that was warmed) shows its data
/// in the first frame instead of starting from a loading state.
const briefKeepAliveDuration = Duration(seconds: 45);

/// Most providers that may sit kept-alive without a listener at once. A person
/// stepping through many days quickly leaves one set per day behind; beyond
/// this the oldest idle one is released early, so memory stays bounded by
/// count as well as by time.
const maxIdleKeptProviders = 48;

/// Idle (kept, no listener) providers, oldest first.
final _idle = <_IdleKept>[];

class _IdleKept {
  _IdleKept(this.release);

  final void Function() release;
}

/// Keeps an auto-dispose provider alive for [duration] after its last listener
/// leaves, so coming back to it shows its value in the first frame.
///
/// A kept provider is NEVER shown older than the database: while it has no
/// listener, any write to the database releases it (it is disposed and the
/// next listener starts fresh), so a value that is shown again was current at
/// the moment it was left and nothing has been written since. That also means
/// an idle kept provider does no work. While something listens, the provider
/// behaves exactly like an ordinary one and follows the database itself.
///
/// For Drift/table-driven streams only. Do not use it for one-off `Future`
/// reads.
void keepAliveBriefly(Ref ref, {Duration duration = briefKeepAliveDuration}) {
  final link = ref.keepAlive();
  final database = ref.read(appDatabaseProvider);
  Timer? timer;
  StreamSubscription<Object?>? writes;
  late final _IdleKept self;

  void stopWaiting() {
    timer?.cancel();
    timer = null;
    writes?.cancel();
    writes = null;
    _idle.remove(self);
  }

  void release() {
    stopWaiting();
    link.close();
  }

  self = _IdleKept(release);

  void becomeIdle() {
    stopWaiting();
    // Root zone: this is housekeeping, not UI time, so widget tests that run
    // on fake time do not see it as a pending timer. It is cancelled when the
    // provider (or its container) is disposed.
    timer = Zone.root.createTimer(duration, release);
    writes = database.tableUpdates().listen((_) => release());
    _idle.add(self);
    while (_idle.length > maxIdleKeptProviders) {
      _idle.first.release();
    }
  }

  // Idle from creation too, so a provider that is only read once is released.
  becomeIdle();
  ref.onAddListener(stopWaiting);
  ref.onCancel(becomeIdle);
  ref.onDispose(stopWaiting);
}
