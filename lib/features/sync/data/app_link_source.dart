import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/auth_callback.dart';
import '../../../core/config/management_callback.dart';

/// The single app-lifetime source of incoming Planner deep links.
///
/// Three facts shape this class:
///
/// 1. `AppLinks().stringLinkStream` is a broadcast wrapper over **one**
///    single-subscription platform stream, and both platforms replay the
///    initial link only to its first subscriber. The Planner therefore
///    subscribes exactly once and fans the links out, so the Planner Auth
///    callback router and the provisioning UI can never steal each other's
///    initial link.
/// 2. The Planner handles deep links while it is still local-only (cloud setup
///    is not finished yet), so this source exists for the whole app lifetime,
///    not only while a provisioned runtime client exists.
/// 3. On Linux a cold start delivered by `xdg-open` reaches the process as a
///    command-line argument, which Flutter hands to `main`. The native
///    `command-line` signal can fire before the Dart method-channel handler
///    exists, so those arguments are replayed here instead of being lost.
///
/// Links are buffered until the first listener attaches, so a link that
/// arrives during startup is still delivered.
class AppLinkSource {
  AppLinkSource({
    Stream<String>? platformLinks,
    this.launchArguments = const <String>[],
  }) : _platformLinks = platformLinks ?? AppLinks().stringLinkStream;

  /// A source that never emits.
  ///
  /// Used by isolated provider containers that the app bootstrap did not
  /// create, so they can never open a second subscription to the single
  /// platform stream (which would steal the initial link from the real one).
  AppLinkSource.inert() : this(platformLinks: const Stream<String>.empty());

  /// How long a platform re-delivery of a launch-argument link is suppressed.
  ///
  /// A cold start on Linux can deliver the same URI twice: once as a process
  /// argument and once through the native command-line signal. Suppressing the
  /// duplicate only inside this short window keeps a genuine user re-tap (a
  /// replay the app must still classify and report) working normally.
  static const Duration duplicateWindow = Duration(seconds: 10);

  static const int _maxBufferedLinks = 8;

  final Stream<String> _platformLinks;

  /// Process launch arguments that may carry a cold-start Planner link.
  final List<String> launchArguments;

  late final StreamController<String> _controller =
      // Flushing on a microtask, because a broadcast controller does not
      // deliver an event added synchronously from its own `onListen`.
      StreamController<String>.broadcast(
        onListen: () => scheduleMicrotask(_flushBuffer),
      );
  final List<String> _buffer = <String>[];
  final Map<String, DateTime> _launchLinks = <String, DateTime>{};
  StreamSubscription<String>? _subscription;
  bool _started = false;
  bool _disposed = false;
  DateTime Function() _clock = DateTime.now;

  /// Every incoming Planner link, in arrival order.
  Stream<String> get links => _controller.stream;

  /// Starts observing platform links and replays launch arguments.
  ///
  /// Safe to call more than once; later calls are ignored.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    for (final argument in launchArguments) {
      if (isPlannerLink(argument)) _recordLaunchLink(argument);
    }
    _subscription = _platformLinks.listen(
      _onPlatformLink,
      onError: (Object _, StackTrace _) {
        // A platform link-stream error is never a reason to disturb the local
        // Planner; the next delivered link is handled normally.
      },
    );
  }

  /// True when [link] is one of the Planner's own callback destinations.
  static bool isPlannerLink(String link) =>
      AuthCallback.tryParse(link) != null || ManagementCallback.matches(link);

  void _recordLaunchLink(String link) {
    _launchLinks[link] = _clock();
    _emit(link);
  }

  void _onPlatformLink(String link) {
    if (_disposed || link.isEmpty) return;
    final now = _clock();
    _launchLinks.removeWhere(
      (_, recordedAt) => now.difference(recordedAt) > duplicateWindow,
    );
    if (_launchLinks.containsKey(link)) {
      // The same URI already arrived through this process's launch arguments.
      _launchLinks.remove(link);
      return;
    }
    _emit(link);
  }

  void _emit(String link) {
    if (_disposed) return;
    if (_controller.hasListener) {
      _controller.add(link);
      return;
    }
    if (_buffer.length == _maxBufferedLinks) _buffer.removeAt(0);
    _buffer.add(link);
  }

  void _flushBuffer() {
    if (_buffer.isEmpty) return;
    final pending = List<String>.of(_buffer);
    _buffer.clear();
    for (final link in pending) {
      _controller.add(link);
    }
  }

  /// Stops observing links. Idempotent; owned by the app bootstrap.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }

  @visibleForTesting
  void configureForTesting({required DateTime Function() clock}) {
    _clock = clock;
  }
}
