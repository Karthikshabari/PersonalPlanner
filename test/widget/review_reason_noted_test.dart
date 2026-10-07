import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../helpers/test_container.dart';

void main() {
  final noted = find.byKey(const ValueKey('review-reason-noted'));

  Future<(ProviderContainer, Finder)> pumpReasonField(
    WidgetTester tester,
  ) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 11);
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Deep work',
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              createdAt: now,
              updatedAt: now,
            ),
          ),
    );
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .taskDao
          .getTasksBetween(
            DateTime(now.year, now.month, now.day),
            DateTime(now.year, now.month, now.day + 1),
          ),
    );
    final id = TaskRepository.fromRow(rows.single).id;
    appRouter.go('/review');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return (container, find.byKey(ValueKey('review-reason-$id')));
  }

  Future<void> blur(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
  }

  testWidgets('indicator is hidden initially', (tester) async {
    final (container, _) = await pumpReasonField(tester);

    expect(noted, findsNothing);
    await finish(tester, container);
  });

  testWidgets('shown after blur with text, as Noted and never Saved', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (container, field) = await pumpReasonField(tester);

    await tester.tap(field);
    await tester.enterText(field, 'Meeting ran long');
    await settle(tester);
    expect(noted, findsNothing);
    final heightBefore = tester.getSize(field).height;

    await blur(tester);

    expect(noted, findsOneWidget);
    expect(tester.getSize(field).height, heightBefore);
    expect(find.descendant(of: noted, matching: find.text('Noted')), findsOne);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.bySemanticsLabel('Reason noted'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    handle.dispose();
    await finish(tester, container);
  });

  testWidgets('shown after pressing Enter', (tester) async {
    final (container, field) = await pumpReasonField(tester);

    await tester.tap(field);
    await tester.enterText(field, 'Waiting on a reply');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(noted, findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('hidden for empty or blank text', (tester) async {
    final (container, field) = await pumpReasonField(tester);

    await tester.tap(field);
    await blur(tester);
    expect(noted, findsNothing);

    await tester.tap(field);
    await tester.enterText(field, '   ');
    await blur(tester);
    expect(noted, findsNothing);
    await finish(tester, container);
  });

  testWidgets('hidden when the field is focused again and returns on blur', (
    tester,
  ) async {
    final (container, field) = await pumpReasonField(tester);
    await tester.tap(field);
    await tester.enterText(field, 'Too tired');
    await blur(tester);
    expect(noted, findsOneWidget);

    await tester.tap(field);
    await settle(tester);
    expect(noted, findsNothing);

    await blur(tester);
    expect(noted, findsOneWidget);

    await tester.tap(field);
    await tester.enterText(field, '');
    await blur(tester);
    expect(noted, findsNothing);
    await finish(tester, container);
  });

  testWidgets('shown after tapping a preset chip', (tester) async {
    final (container, field) = await pumpReasonField(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Blocked'));
    await settle(tester);

    expect(tester.widget<TextField>(field).controller!.text, 'Blocked');
    expect(noted, findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('fades in over about 180 ms by default', (tester) async {
    final (container, field) = await pumpReasonField(tester);
    await tester.tap(field);
    await tester.enterText(field, 'Too tired');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    double opacity() => tester
        .widget<Opacity>(
          find.descendant(of: noted, matching: find.byType(Opacity)),
        )
        .opacity;
    expect(opacity(), lessThan(1));

    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 1);
    await finish(tester, container);
  });

  testWidgets('no animation when animations are disabled', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final (container, field) = await pumpReasonField(tester);
    await tester.tap(field);
    await tester.enterText(field, 'Too tired');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(noted, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.descendant(of: noted, matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 1);
    await finish(tester, container);
  });
}
