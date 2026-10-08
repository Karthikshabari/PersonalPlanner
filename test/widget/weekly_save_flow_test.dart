import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/review/providers/weekly_review_draft_controller.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

class _FailingReviewRepository extends ReviewRepository {
  _FailingReviewRepository(super.db);

  @override
  Future<WeeklyReview> saveWeeklyReviewDraft({
    required DateTime weekStart,
    required int mood,
    required String feeling,
    required String note,
  }) async => throw StateError('disk full');
}

void main() {
  final saveButton = find.byKey(const ValueKey('weekly-save'));
  final feelingField = find.byKey(const ValueKey('weekly-feeling'));
  final pill = find.byKey(const ValueKey('weekly-unsaved-pill'));
  DateTime thisWeek() => startOfWeek(DateTime.now());

  // Leaving the Weekly tab disposes reactive-stats providers; give their
  // async onCancel real time so database.close() in finish() does not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  Future<ProviderContainer> pumpWeekly(
    WidgetTester tester, {
    Size surface = const Size(1400, 1000),
    ProviderContainer? container,
  }) async {
    final c = container ?? await buildTestContainer(tester);
    final start = thisWeek().add(const Duration(hours: 9));
    await runDb(
      tester,
      () => c
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Write report',
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
    appRouter.go('/review/weekly');
    await pumpApp(tester, c, surface: surface);
    await settle(tester);
    return c;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveButton);
    await settle(tester);
  }

  String feelingText(WidgetTester tester) =>
      tester.widget<TextField>(feelingField).controller!.text;

  testWidgets('Saved with a check, then any edit returns to Save review', (
    tester,
  ) async {
    final container = await pumpWeekly(tester);
    expect(find.text('Save review'), findsOneWidget);

    await tapSave(tester);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-save-check')), findsOneWidget);

    await tester.tap(find.text('Calm'));
    await settle(tester);
    expect(find.text('Save review'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('Not saved yet pill follows the draft', (tester) async {
    final container = await pumpWeekly(tester);
    expect(pill, findsNothing);

    await tester.tap(find.byKey(const ValueKey('weekly-mood-2')));
    await settle(tester);
    expect(pill, findsOneWidget);
    expect(
      find.descendant(of: pill, matching: find.text('Not saved yet')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('weekly-mood-1')));
    await settle(tester);
    expect(pill, findsNothing);
    await finish(tester, container);
  });

  testWidgets('Ctrl + Enter and Cmd + Enter save; hint only when wide', (
    tester,
  ) async {
    final container = await pumpWeekly(tester);
    expect(find.text('Ctrl + Enter'), findsOneWidget);

    await tester.tap(feelingField);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(find.text('Saved'), findsOneWidget);

    await tester.enterText(feelingField, 'Busy');
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    expect(find.text('Saved'), findsOneWidget);
    final WeeklyReview? saved = await runDb(
      tester,
      () => container
          .read(reviewRepositoryProvider)
          .getWeeklyReviewForWeek(thisWeek()),
    );
    expect(saved!.feeling, startsWith('Busy'));
    await finish(tester, container);
  });

  testWidgets('no shortcut hint on a narrow layout', (tester) async {
    final container = await pumpWeekly(tester, surface: const Size(390, 844));
    expect(find.text('Ctrl + Enter'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('snackbar offers See in Overview', (tester) async {
    final container = await pumpWeekly(tester);
    await tapSave(tester);
    expect(find.text('Review saved'), findsOneWidget);

    await tester.tap(find.text('See in Overview'));
    await settle(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Overview')),
      findsOneWidget,
    );
    // Two drains: leaving Weekly disposes its reactive streams, and the
    // Overview's own reads must finish before the database closes.
    await drainDisposedStreams(tester);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('failure shows the error snackbar and keeps the draft', (
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
    await pumpWeekly(tester, container: container);

    await tester.tap(find.text('Tired'));
    await settle(tester);
    await tapSave(tester);

    expect(find.text('Couldn\'t save the review. Try again.'), findsOneWidget);
    expect(find.text('Save review'), findsOneWidget);
    expect(feelingText(tester), 'Tired');
    await finish(tester, container);
  });

  testWidgets('saving from Next week switches back to Review', (tester) async {
    final container = await pumpWeekly(tester);
    await tester.tap(find.text('Next week (optional)'));
    await settle(tester);
    expect(find.text('Week at a glance'), findsNothing);

    await tapSave(tester);
    expect(find.text('Week at a glance'), findsOneWidget);
    expect(find.text('A note for next week'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('an unsaved weekly draft survives leaving and returning', (
    tester,
  ) async {
    final container = await pumpWeekly(tester);
    await tester.enterText(feelingField, 'Long but calm');
    await settle(tester);
    expect(pill, findsOneWidget);

    appRouter.go('/review');
    await settle(tester);
    await drainDisposedStreams(tester);
    appRouter.go('/review/weekly');
    await settle(tester);

    expect(feelingText(tester), 'Long but calm');
    expect(pill, findsOneWidget);
    expect(
      container.read(weeklyReviewDraftKeeperProvider).holds(thisWeek()),
      isTrue,
    );
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('narrow: the first save centres Your week', (tester) async {
    final container = await pumpWeekly(tester, surface: const Size(390, 844));
    final reveal = find.byKey(const ValueKey('weekly-reveal'));
    final before = tester.getCenter(reveal).dy;

    await tapSave(tester);

    final after = tester.getCenter(reveal).dy;
    expect(after, isNot(before));
    expect(after, greaterThan(0));
    expect(after, lessThan(844));
    await finish(tester, container);
  });

  testWidgets('haptic tick after save only on Android', (tester) async {
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
    final container = await pumpWeekly(tester);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tapSave(tester);
    expect(calls, isEmpty);

    await tester.enterText(feelingField, 'edit');
    await settle(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tapSave(tester);
    expect(calls, ['HapticFeedbackType.lightImpact']);
    await finish(tester, container);
  });
}
