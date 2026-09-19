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
    DateTime? now,
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
              now: now ?? DateTime(2026, 9, 19, 21, 50),
              onSyncNow: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('idle healthy state shows up to date without animating', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: SyncStatusSnapshot(
        state: SyncEngineState.synced,
        lastSuccessfulSync: DateTime(2026, 9, 19, 21, 47),
      ),
    );

    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Last synced 3 minutes ago'), findsOneWidget);
    // Idle never animates, even though sync is enabled.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Sync now'), findsOneWidget);

    // The action is never disabled by an idle state.
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('sync-now-action')),
    );
    expect(button.onPressed, isNotNull);
  });

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
    expect(find.text('Cloud Sync is off'), findsOneWidget);
    expect(find.textContaining('Pending changes stay queued'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sync-now-action')))
          .onPressed,
      isNull,
    );
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
    expect(find.text('Last synced 50 minutes ago'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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
  });
}
