import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/task_template.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/templates/providers/template_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpTemplates(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    // The global router keeps its location across tests in this file.
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    // Settings → Task Templates.
    await tester.tap(find.text('Settings').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('templates-tile')));
    await settle(tester);
    return container;
  }

  testWidgets('settings tile navigates to the templates screen', (
    tester,
  ) async {
    final container = await pumpTemplates(tester);
    expect(find.text('Task Templates'), findsWidgets);
    expect(find.textContaining('No templates yet'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('create a template via the FAB form', (tester) async {
    final container = await pumpTemplates(tester);

    await tester.tap(find.byKey(const ValueKey('add-template-fab')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('template-form-name')),
      'Deep Work',
    );
    final durationField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Duration (minutes)',
    );
    await tester.enterText(durationField, '90');
    await tester.tap(find.byKey(const ValueKey('template-form-save')));
    await settle(tester);

    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.textContaining('90 min'), findsOneWidget);
    final all = await runDb(
      tester,
      () => container.read(templateRepositoryProvider).getAllTemplates(),
    );
    expect(all.single.name, 'Deep Work');
    expect(all.single.durationMin, 90);
    await finish(tester, container);
  });

  testWidgets('edit renames a template', (tester) async {
    final container = await pumpTemplates(tester);
    await runDb(
      tester,
      () => container
          .read(templateRepositoryProvider)
          .insertTemplate(
            TaskTemplate(
              id: '',
              name: 'Old name',
              durationMin: 30,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    // Navigate again (fresh app starts on /day).
    await tester.tap(find.text('Settings').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('templates-tile')));
    await settle(tester);

    await tester.tap(find.byTooltip('Edit'));
    await settle(tester);
    final field = find.byKey(const ValueKey('template-form-name'));
    await tester.enterText(field, 'New name');
    await tester.tap(find.byKey(const ValueKey('template-form-save')));
    await settle(tester);

    expect(find.text('New name'), findsOneWidget);
    expect(find.text('Old name'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('delete asks for confirmation and removes the template', (
    tester,
  ) async {
    final container = await pumpTemplates(tester);
    final created = await runDb(
      tester,
      () => container
          .read(templateRepositoryProvider)
          .insertTemplate(
            TaskTemplate(
              id: '',
              name: 'Doomed',
              durationMin: 15,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await tester.tap(find.text('Settings').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('templates-tile')));
    await settle(tester);

    await tester.tap(find.byKey(ValueKey('delete-template-${created.id}')));
    await settle(tester);
    expect(find.text('Delete template?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    expect(find.text('Doomed'), findsNothing);
    final all = await runDb(
      tester,
      () => container.read(templateRepositoryProvider).getAllTemplates(),
    );
    expect(all, isEmpty);
    await finish(tester, container);
  });

  testWidgets('"Use template" pre-fills editor fields', (tester) async {
    final container = await buildTestContainer(tester);
    final categoryRepo = container.read(categoryRepositoryProvider);
    final work = (await runDb(
      tester,
      () => categoryRepo.getAllCategories(),
    )).singleWhere((c) => c.name == 'Work');
    await runDb(
      tester,
      () => container
          .read(templateRepositoryProvider)
          .insertTemplate(
            TaskTemplate(
              id: '',
              name: 'Gym session',
              description: 'Warmup + strength',
              durationMin: 45,
              categoryId: work.id,
              priority: 2,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );

    final now = DateTime.now();
    final inserted = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Empty slot',
              startTime: DateTime(now.year, now.month, now.day, now.hour),
              endTime: DateTime(now.year, now.month, now.day, now.hour + 1),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ),
    );
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await tester.tap(find.text('Empty slot'));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${inserted.id}')));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), inserted.id);

    // Pick the template from the dropdown.
    final dropdown = find.byKey(const ValueKey('use-template-dropdown'));
    await bringIntoViewHelper(tester, dropdown);
    await tester.tap(dropdown);
    await settle(tester);
    await tester.tap(find.text('Gym session').last);
    await settle(tester);

    // Fields pre-filled (title/description/duration/category).
    final titleField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Title',
    );
    expect(
      tester.widget<TextField>(titleField).controller!.text,
      'Gym session',
    );
    final descField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Description',
    );
    expect(
      tester.widget<TextField>(descField).controller!.text,
      'Warmup + strength',
    );
    expect(find.text('Planned duration: 45 minutes'), findsOneWidget);
    expect(find.text('Priority'), findsNothing);
    expect(find.text('Tags'), findsNothing);

    await finish(tester, container);
  });

  testWidgets('"Save as template" creates one from current fields', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final inserted = await runDb(tester, () {
      final now = DateTime.now();
      return container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Weekly review prep',
              startTime: DateTime(now.year, now.month, now.day, now.hour),
              endTime: DateTime(now.year, now.month, now.day, now.hour + 1),
              estimatedDurationMin: 25,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    });
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    await tester.tap(find.text('Weekly review prep'));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${inserted.id}')));
    await settle(tester);

    final titleField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Title',
    );
    final descriptionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Description',
    );
    await tester.enterText(titleField, 'Unsaved focus plan');
    await tester.enterText(descriptionField, 'Draft details');

    final button = find.byKey(const ValueKey('save-as-template-button'));
    await bringIntoViewHelper(tester, button);
    await tester.tap(button);
    await settle(tester);

    // Name and fields come from the unsaved editor draft, not the source row.
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('template-name-field')),
    );
    expect(nameField.controller!.text, 'Unsaved focus plan');
    await tester.tap(find.byKey(const ValueKey('template-save-confirm')));
    await settle(tester);

    final templates = await runDb(
      tester,
      () => container.read(templateRepositoryProvider).getAllTemplates(),
    );
    expect(templates.single.name, 'Unsaved focus plan');
    expect(templates.single.description, 'Draft details');
    expect(templates.single.durationMin, 60);
    // Sanity: source task still exists and is untouched.
    final source = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(inserted.id),
    );
    expect(source!.title, 'Weekly review prep');
    expect(source.description, isNull);
    expect(source.estimatedDurationMin, 60);
    await finish(tester, container);
  });
}

/// Local copy of the helper used by the recurrence tests (bringIntoView).
Future<void> bringIntoViewHelper(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final editorScrollable = find
      .ancestor(of: target, matching: find.byType(Scrollable))
      .last;
  final scrollable = tester.state<ScrollableState>(editorScrollable);
  final before = tester.getRect(target);
  final viewport = tester.getRect(editorScrollable);
  final desiredTop = viewport.top + 80;
  final targetPixels = (scrollable.position.pixels + before.top - desiredTop)
      .clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      );
  scrollable.position.jumpTo(targetPixels.toDouble());
  await settle(tester);
  final rect = tester.getRect(target);
  if (rect.bottom <= viewport.top || rect.top >= viewport.bottom) {
    fail('target never became visible: $target');
  }
}
