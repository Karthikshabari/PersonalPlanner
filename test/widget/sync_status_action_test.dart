import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/presentation/widgets/sync_status_action.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';

import '../helpers/test_container.dart';

/// UAT F-014: the sync-status icon must not stack Sync pages.
void main() {
  testWidgets('sync icon on the Sync page does not push another copy', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/inbox');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(appRouter.state.uri.path, '/inbox');

    // From another screen the icon still opens Sync settings.
    await tester.tap(find.byKey(const ValueKey('sync-status-action')));
    await settle(tester);
    expect(appRouter.state.uri.path, '/settings/sync');

    // On the Sync page itself, repeated taps are inert.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('sync-status-action')));
      await settle(tester);
    }
    expect(appRouter.state.uri.path, '/settings/sync');

    // One Back returns to where the user came from.
    appRouter.pop();
    await settle(tester);
    expect(appRouter.state.uri.path, '/inbox');
    await finish(tester, container);
  });

  group('visual states', () {
    const key = ValueKey('sync-status-action');

    // Every SyncEngineState must be listed here (see the coverage test).
    final expected =
        <
          SyncEngineState,
          ({
            IconData icon,
            Color Function(AppThemeTokens) color,
            bool errorDot,
            String tooltip,
          })
        >{
          SyncEngineState.synced: (
            icon: Icons.cloud_done_outlined,
            color: (t) => t.success,
            errorDot: false,
            tooltip: 'Sync: Synced',
          ),
          SyncEngineState.syncing: (
            icon: Icons.sync,
            color: (t) => t.info,
            errorDot: false,
            tooltip: 'Sync: Syncing',
          ),
          SyncEngineState.pending: (
            icon: Icons.schedule,
            color: (t) => t.info,
            errorDot: false,
            tooltip: 'Sync: Pending',
          ),
          SyncEngineState.initialSyncPending: (
            icon: Icons.schedule,
            color: (t) => t.info,
            errorDot: false,
            tooltip: 'Sync: Cloud setup pending',
          ),
          SyncEngineState.refreshPaused: (
            icon: Icons.schedule,
            color: (t) => t.info,
            errorDot: false,
            tooltip: 'Sync: Waiting for session refresh',
          ),
          SyncEngineState.offline: (
            icon: Icons.cloud_off_outlined,
            color: (t) => t.offline,
            errorDot: false,
            tooltip: 'Sync: Offline',
          ),
          SyncEngineState.backendUnavailable: (
            icon: Icons.cloud_off_outlined,
            color: (t) => t.offline,
            errorDot: false,
            tooltip: 'Sync: Backend unavailable',
          ),
          SyncEngineState.error: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Error',
          ),
          SyncEngineState.conflict: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Conflict',
          ),
          SyncEngineState.partialSuccess: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Partially synced',
          ),
          SyncEngineState.permanentFailure: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Action required',
          ),
          SyncEngineState.authFailure: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Sign-in required',
          ),
          SyncEngineState.invalidData: (
            icon: Icons.cloud_off,
            color: (t) => t.error,
            errorDot: true,
            tooltip: 'Sync: Invalid data',
          ),
          SyncEngineState.notConfigured: (
            icon: Icons.cloud_queue_outlined,
            color: (t) => t.textMuted,
            errorDot: false,
            tooltip: 'Local only. Set up cloud sync',
          ),
        };

    Future<void> pumpAction(
      WidgetTester tester,
      Stream<SyncStatusSnapshot> stream, {
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncStatusProvider.overrideWith((ref) => stream)],
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: const Scaffold(body: Center(child: SyncStatusAction())),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Finder dot() => find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 8 && w.height == 8,
      ),
    );

    Finder spinner() => find.descendant(
      of: find.byKey(key),
      matching: find.byType(RotationTransition),
    );

    test('every one of the 14 states has an expectation', () {
      expect(expected.keys.toSet(), SyncEngineState.values.toSet());
      expect(SyncEngineState.values, hasLength(14));
    });

    for (final state in SyncEngineState.values) {
      testWidgets('${state.name} shows its icon, colour, dot and tooltip', (
        tester,
      ) async {
        final want = expected[state]!;
        await pumpAction(
          tester,
          Stream.value(SyncStatusSnapshot(state: state)),
        );
        final tokens = AppThemeTokens.of(
          tester.element(find.byType(SyncStatusAction)),
        );
        final icon = tester.widget<Icon>(
          find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
        );
        expect(icon.icon, want.icon);
        expect(icon.color, want.color(tokens));
        expect(dot(), want.errorDot ? findsOneWidget : findsNothing);
        expect(find.byTooltip(want.tooltip), findsOneWidget);
        // 48dp target.
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        // Only syncing rotates; every other state has no ticker at all.
        final rotating = find.descendant(
          of: find.byKey(key),
          matching: find.byType(RotationTransition),
        );
        expect(
          rotating,
          state == SyncEngineState.syncing ? findsOneWidget : findsNothing,
        );
        if (state != SyncEngineState.syncing) {
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
      });
    }

    testWidgets('tooltip and semantics carry counts and last sync time', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAction(
        tester,
        Stream.value(
          SyncStatusSnapshot(
            state: SyncEngineState.pending,
            pendingOperations: 3,
            conflictCount: 1,
            lastSuccessfulSync: DateTime(2026, 10, 14, 14, 5),
          ),
        ),
      );
      const text =
          'Sync: Pending · 3 pending · 1 conflict(s) · Last synced 14:05';
      expect(find.byTooltip(text), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(key)),
        matchesSemantics(
          label: text,
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('rotation starts on syncing and its ticker ends after it', (
      tester,
    ) async {
      final controller = StreamController<SyncStatusSnapshot>();
      addTearDown(controller.close);
      await pumpAction(tester, controller.stream);
      controller.add(const SyncStatusSnapshot(state: SyncEngineState.syncing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(spinner(), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isTrue);

      controller.add(const SyncStatusSnapshot(state: SyncEngineState.synced));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(spinner(), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);

      // A second sync starts a fresh controller on the same State.
      controller.add(const SyncStatusSnapshot(state: SyncEngineState.syncing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(spinner(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion keeps the syncing icon static', (tester) async {
      await pumpAction(
        tester,
        Stream.value(const SyncStatusSnapshot(state: SyncEngineState.syncing)),
        disableAnimations: true,
      );
      expect(spinner(), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
            )
            .icon,
        Icons.sync,
      );
    });

    testWidgets('a status stream error shows the error state', (tester) async {
      await pumpAction(tester, Stream.error(StateError('boom')));
      expect(dot(), findsOneWidget);
      expect(
        find.byTooltip('Sync status unavailable. Open Sync settings to retry.'),
        findsOneWidget,
      );
    });
  });
}
