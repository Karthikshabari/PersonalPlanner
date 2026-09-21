import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/presentation/widgets/sync_action_group.dart';
import 'package:personal_planner/features/sync/presentation/widgets/sync_status_card.dart';

/// Sync-status presentation: still when idle, active only during real work, and
/// responsive by available width rather than by platform.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required SyncStatusSnapshot status,
    bool enabled = true,
    double width = 420,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SyncStatusPanel(
              status: status,
              enabled: enabled,
              busy: false,
              onSyncNow: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'idle healthy state shows synced without a timestamp or animation',
    (tester) async {
      await pumpPanel(
        tester,
        status: SyncStatusSnapshot(
          state: SyncEngineState.synced,
          lastSuccessfulSync: DateTime(2026, 9, 19, 21, 47),
        ),
      );

      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Your Planner data is synchronized.'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsNothing);
      // Idle never animates, even though sync is enabled.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Sync now'), findsOneWidget);

      // The action is never disabled by an idle state.
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('sync-now-action')),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('an active sync cycle is visibly active', (tester) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(state: SyncEngineState.syncing),
    );

    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-active-indicator')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('paused states are described plainly', (tester) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(state: SyncEngineState.offline),
    );
    expect(find.text('Cloud sync paused'), findsOneWidget);
    expect(
      find.textContaining("You're offline. Changes will sync"),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await pumpPanel(
      tester,
      enabled: false,
      status: const SyncStatusSnapshot(state: SyncEngineState.synced),
    );
    expect(find.text('Sync is off'), findsOneWidget);
    expect(
      find.text(
        'Changes will stay on this device until you turn sync back on.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sync-now-action')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an incomplete cycle explains itself and offers a retry', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(
        state: SyncEngineState.error,
        message: 'Your changes are safe on this device.',
      ),
    );

    expect(find.text("Couldn't sync"), findsOneWidget);
    expect(find.text('Your changes are safe on this device.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Nothing has ever completed, and the timestamp-era extra line is gone.
    expect(find.text('Not synced yet'), findsNothing);
    expect(find.textContaining('Last successful sync at'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('pending work is reported compactly without animating', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: SyncStatusSnapshot(
        state: SyncEngineState.pending,
        pendingOperations: 3,
        lastSuccessfulSync: DateTime(2026, 9, 19, 21, 0),
      ),
    );

    expect(find.text('Waiting to sync'), findsOneWidget);
    expect(find.text('3 changes are waiting to sync.'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsNothing);
    expect(
      find.text('Changes will sync when the cloud connection is available.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an account that never synced is never called up to date', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(state: SyncEngineState.synced),
    );

    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
    expect(find.textContaining('Last synced at'), findsNothing);
  });

  testWidgets('an unreachable cloud keeps the previous successful instant', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: SyncStatusSnapshot(
        state: SyncEngineState.backendUnavailable,
        message: 'Your cloud backend could not be reached.',
        lastSuccessfulSync: DateTime(2026, 9, 19, 23, 42),
      ),
    );

    expect(find.text("Couldn't reach cloud storage"), findsOneWidget);
    expect(
      find.text('Your cloud backend could not be reached.'),
      findsOneWidget,
    );
    expect(find.textContaining('Last successful sync at'), findsNothing);
    // A temporary outage never claims a fresh successful synchronization.
    expect(find.text('Synced'), findsNothing);
    expect(find.textContaining('Last synced at'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an unreachable cloud that never synced invents no instant', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(
        state: SyncEngineState.backendUnavailable,
      ),
    );

    expect(find.text("Couldn't reach cloud storage"), findsOneWidget);
    expect(find.text('Not synced yet'), findsNothing);
    expect(find.textContaining('Last successful sync at'), findsNothing);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('a later failure keeps the last successful instant', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: SyncStatusSnapshot(
        state: SyncEngineState.error,
        message: 'Network unavailable; retry scheduled.',
        lastSuccessfulSync: DateTime(2026, 9, 19, 23, 53),
      ),
    );

    expect(find.text("Couldn't sync"), findsOneWidget);
    expect(find.text('Network unavailable; retry scheduled.'), findsOneWidget);
    expect(find.textContaining('Last successful sync at'), findsNothing);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('re-authorization is requested instead of a deleted project', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: const SyncStatusSnapshot(
        state: SyncEngineState.authFailure,
        message: 'Session ended. Sign in again.',
      ),
    );

    expect(find.text('Reauthorization required'), findsOneWidget);
    expect(find.text('Session ended. Sign in again.'), findsOneWidget);
    expect(find.textContaining('Project unavailable'), findsNothing);
  });

  testWidgets('the sync panel never exposes the last-sync timestamp', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: SyncStatusSnapshot(
        state: SyncEngineState.synced,
        lastSuccessfulSync: DateTime(2026, 9, 19, 21, 47),
      ),
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsNothing);

    // Any relative wording ("just now", "5 minutes ago") would have changed
    // here, and a pending per-second timer would fail the test at teardown.
    await tester.pump(const Duration(minutes: 5));
    await tester.pump(const Duration(hours: 3));
    expect(find.text('Synced'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsNothing);
    expect(find.textContaining('ago'), findsNothing);
    expect(find.textContaining('Just now'), findsNothing);
  });

  testWidgets('android and linux render the same semantic status', (
    tester,
  ) async {
    Future<List<String>> render(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pumpPanel(
          tester,
          status: SyncStatusSnapshot(
            state: SyncEngineState.backendUnavailable,
            lastSuccessfulSync: DateTime(2026, 9, 19, 23, 42),
          ),
        );
        final texts = <String>[];
        for (final element
            in find
                .byType(Text)
                .evaluate()
                .map((element) => element.widget)
                .whereType<Text>()) {
          if (element.data != null) texts.add(element.data!);
        }
        return texts;
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    final android = await render(TargetPlatform.android);
    final linux = await render(TargetPlatform.linux);

    expect(android, linux);
    expect(android, contains("Couldn't reach cloud storage"));
    expect(android, contains('Try again'));
  });

  testWidgets('actions stack on a phone and share a row on a wider surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: SyncActionGroup(
                actions: <Widget>[
                  OutlinedButton(onPressed: () {}, child: const Text('First')),
                  FilledButton(onPressed: () {}, child: const Text('Second')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final narrowFirst = tester.getTopLeft(find.text('First'));
    final narrowSecond = tester.getTopLeft(find.text('Second'));
    expect(
      narrowSecond.dy,
      greaterThan(narrowFirst.dy),
      reason: 'narrow widths must stack instead of squeezing two buttons',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 720,
              child: SyncActionGroup(
                actions: <Widget>[
                  OutlinedButton(onPressed: () {}, child: const Text('First')),
                  FilledButton(onPressed: () {}, child: const Text('Second')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Second')).dy,
      tester.getTopLeft(find.text('First')).dy,
      reason: 'wide widths must keep the actions on one row',
    );
    expect(tester.takeException(), isNull);
  });

  group('formatSyncTimestamp', () {
    final now = DateTime(2026, 9, 19, 21, 50, 30);

    test('prefers human-friendly wording over a raw instant', () {
      expect(
        formatSyncTimestamp(now.subtract(const Duration(seconds: 5)), now: now),
        'Just now',
      );
      expect(
        formatSyncTimestamp(now.subtract(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        formatSyncTimestamp(now.subtract(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        formatSyncTimestamp(DateTime(2026, 9, 19, 9, 47), now: now),
        'Today at 9:47 AM',
      );
      expect(
        formatSyncTimestamp(DateTime(2026, 9, 18, 21, 47), now: now),
        'Yesterday at 9:47 PM',
      );
      expect(
        formatSyncTimestamp(DateTime(2026, 9, 10, 21, 47), now: now),
        '2026-09-10 at 9:47 PM',
      );
    });

    test('never prints microseconds', () {
      expect(
        formatSyncTimestamp(
          DateTime(2026, 9, 19, 21, 47, 59, 859, 625),
          now: now,
        ),
        isNot(contains('.')),
      );
    });

    test('the sync panel clock form is absolute', () {
      expect(formatSyncClockTime(DateTime(2026, 9, 19, 23, 51)), '11:51 PM');
      expect(formatSyncClockTime(DateTime(2026, 9, 19, 0, 5)), '12:05 AM');
      expect(formatSyncClockTime(DateTime(2026, 9, 19, 12, 0)), '12:00 PM');
    });
  });
}
