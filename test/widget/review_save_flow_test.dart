import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

class _FailingReviewRepository extends ReviewRepository {
  _FailingReviewRepository(super.db);

  @override
  Future<DailyReview> saveReviewDraft({
    required DateTime date,
    required int mood,
    required String note,
    required Map<String, String> taskReasons,
  }) async => throw StateError('disk full');
}

void main() {
  final saveButton = find.byKey(const ValueKey('review-save'));
  final noteField = find.byKey(const ValueKey('review-note'));

  Future<ProviderContainer> pumpDaily(
    WidgetTester tester, {
    Size surface = const Size(1400, 1000),
  }) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/review');
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await settle(tester);
  }

  // Leaving the Daily tab disposes reactive-stats providers; give their async
  // onCancel real time so database.close() in finish() does not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  testWidgets(
    'save shows Saved with a check, then any edit returns to Save review',
    (tester) async {
      final container = await pumpDaily(tester);
      expect(find.text('Save review'), findsOneWidget);

      await tapSave(tester);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-save-check')), findsOneWidget);

      await tester.enterText(noteField, 'Good day');
      await settle(tester);
      expect(find.text('Save review'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      await finish(tester, container);
    },
  );

  testWidgets('success snackbar offers See in Overview', (tester) async {
    final container = await pumpDaily(tester);
    await tapSave(tester);
    expect(find.text('Review saved'), findsOneWidget);
    expect(find.text('See in Overview'), findsOneWidget);

    await tester.tap(find.text('See in Overview'));
    await settle(tester);
    expect(find.byKey(const ValueKey('overview-strip')), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('snackbar disappears after 4 seconds', (tester) async {
    final container = await pumpDaily(tester);
    await tapSave(tester);
    expect(find.text('Review saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Review saved'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('failure shows the error snackbar and keeps Save review', (
    tester,
  ) async {
    setupSqliteForTests();
    late ProviderContainer container;
    await tester.runAsync(() async {
      final database = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          reviewRepositoryProvider.overrideWithValue(
            _FailingReviewRepository(database),
          ),
        ],
      );
      await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
    });
    appRouter.go('/review');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await tapSave(tester);
    expect(find.text('Couldn\'t save the review. Try again.'), findsOneWidget);
    expect(find.text('Save review'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Review saved'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('Ctrl+Enter saves on desktop', (tester) async {
    final container = await pumpDaily(tester);
    expect(find.text('Ctrl + Enter'), findsOneWidget);

    await tester.tap(noteField);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(find.text('Saved'), findsOneWidget);

    await finish(tester, container);
  });

  testWidgets('shortcut hint is hidden on narrow layouts', (tester) async {
    final container = await pumpDaily(tester, surface: const Size(390, 844));
    expect(find.text('Ctrl + Enter'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('haptic tick only on Android', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = await pumpDaily(tester);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tapSave(tester);
    expect(calls, isEmpty);

    await tester.enterText(noteField, 'edit');
    await settle(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tapSave(tester);
    expect(calls, ['HapticFeedbackType.lightImpact']);
    await finish(tester, container);
  });

  testWidgets('reduced motion swaps the icon without animating', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final container = await pumpDaily(tester);

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('review-save-check')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('status chip scrolls to and focuses Save', (tester) async {
    final container = await pumpDaily(tester, surface: const Size(390, 844));
    final chip = find.byKey(const ValueKey('review-status-chip'));
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, 'review-save');
    await finish(tester, container);
  });
}
