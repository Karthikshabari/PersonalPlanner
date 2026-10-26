import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/task_template.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/templates/data/template_repository.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpCategories(WidgetTester tester) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    // Navigate to the categories screen.
    await tester.tap(find.text('Categories').last);
    await settle(tester);
    return container;
  }

  testWidgets('create a category with name and palette color', (tester) async {
    final container = await pumpCategories(tester);

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Side Projects');
    // Pick the second palette swatch.
    await tester.tap(find.byKey(const ValueKey('palette-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    expect(find.text('Side Projects'), findsOneWidget);
    final all = await runDb(
      tester,
      () => container.read(categoryRepositoryProvider).getAllCategories(),
    );
    expect(all.map((c) => c.name), contains('Side Projects'));
    final created = all.singleWhere((c) => c.name == 'Side Projects');
    expect(created.colorHex, '#4285F4'); // palette[1]
    await finish(tester, container);
  });

  testWidgets('edit renames a category', (tester) async {
    final container = await pumpCategories(tester);
    await tester.tap(find.byKey(const ValueKey('edit-category-Work')));
    await settle(tester);
    // The edit dialog opens pre-filled; rename and save.
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Deep Work');
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.text('Work'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('focus toggle switches isFocus', (tester) async {
    final container = await pumpCategories(tester);
    await tester.tap(find.byTooltip('Focus category').first);
    await settle(tester);
    final work = await runDb(
      tester,
      () async =>
          (await container.read(categoryRepositoryProvider).getAllCategories())
              .singleWhere((c) => c.name == 'Work'),
    );
    expect(work.isFocus, isTrue);
    await finish(tester, container);
  });

  testWidgets(
    'delete asks for confirmation; tasks keep existing but lose the category',
    (tester) async {
      final container = await pumpCategories(tester);
      // Give Work a task first.
      final task = await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Categorized',
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
            ),
      );
      final work = await runDb(
        tester,
        () async =>
            (await container
                    .read(categoryRepositoryProvider)
                    .getAllCategories())
                .singleWhere((c) => c.name == 'Work'),
      );
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .updateTask(task.copyWith(categoryId: work.id)),
      );

      await tester.tap(find.byKey(const ValueKey('delete-category-Work')));
      await settle(tester);
      expect(find.text('Delete category?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-category')));
      await settle(tester);

      expect(find.text('Work'), findsNothing);
      final reloaded = await runDb(
        tester,
        () => container.read(taskRepositoryProvider).getTaskById(task.id),
      );
      expect(reloaded!.categoryId, isNull);
      expect(reloaded.title, 'Categorized');
      await finish(tester, container);
    },
  );

  testWidgets(
    'delete dialog shows counts; past tasks keep the category; Undo restores',
    (tester) async {
      final container = await pumpCategories(tester);
      final db = container.read(appDatabaseProvider);
      final work = await runDb(
        tester,
        () async =>
            (await container
                    .read(categoryRepositoryProvider)
                    .getAllCategories())
                .singleWhere((c) => c.name == 'Work'),
      );
      final now = DateTime.now();
      Future<Task> seed(
        String title,
        int daysAway,
        TaskStatus status,
      ) => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: title,
              categoryId: work.id,
              startTime: DateTime(now.year, now.month, now.day + daysAway, 9),
              endTime: DateTime(now.year, now.month, now.day + daysAway, 10),
              status: status,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final (past, future, rule, template) = await runDb(tester, () async {
        final past = await seed('Past', -7, TaskStatus.completed);
        final future = await seed('Future', 7, TaskStatus.planned);
        final rule = await RecurringRepository(db).createRule(
          RecurringRule(
            id: '',
            rrule: 'FREQ=DAILY',
            taskTitle: 'Rule',
            durationMin: 30,
            startTimeOfDay: '09:00',
            startDate: now,
            categoryId: work.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final template = await TemplateRepository(db).insertTemplate(
          TaskTemplate(
            id: '',
            name: 'Template',
            durationMin: 30,
            categoryId: work.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        return (past, future, rule, template);
      });

      await tester.tap(find.byKey(const ValueKey('delete-category-Work')));
      await settle(tester);
      expect(
        find.textContaining('2 tasks (1 in the past), 1 rule, 1 template'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Past and finished tasks keep'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-category')));
      await settle(tester);

      Future<List<String?>> categoryIds() => runDb(
        tester,
        () async => [
          (await db.taskDao.getTaskById(past.id))!.categoryId,
          (await db.taskDao.getTaskById(future.id))!.categoryId,
          (await RecurringRepository(db).getRuleById(rule.id))!.categoryId,
          (await TemplateRepository(db).getTemplateById(template.id))!
              .categoryId,
        ],
      );
      expect(await categoryIds(), [work.id, null, null, null]);
      expect(find.text('Deleted "Work"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(await categoryIds(), [work.id, work.id, work.id, work.id]);
      expect(find.text('Work'), findsOneWidget);
      await finish(tester, container);
    },
  );

  // UAT F-011: name errors are explained inside the dialog.
  Finder nameFieldText(String text) => find.descendant(
    of: find.byKey(const ValueKey('category-name')),
    matching: find.text(text),
  );

  Future<List<String>> categoryNames(
    WidgetTester tester,
    ProviderContainer container,
  ) async => (await runDb(
    tester,
    () => container.read(categoryRepositoryProvider).getAllCategories(),
  )).map((c) => c.name).toList();

  testWidgets('a name over 100 characters is rejected inline, not saved', (
    tester,
  ) async {
    final container = await pumpCategories(tester);
    final before = await categoryNames(tester, container);

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'LONGCAT${'0123456789' * 25}END',
    );
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    expect(find.text('New category'), findsOneWidget);
    expect(
      nameFieldText('Name must be 100 characters or fewer'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Something went wrong'), findsNothing);
    expect(await categoryNames(tester, container), before);

    // Shortening the name clears the error and saves.
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'c' * 100,
    );
    await settle(tester);
    expect(nameFieldText('Name must be 100 characters or fewer'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);
    expect(find.text('New category'), findsNothing);
    expect(await categoryNames(tester, container), contains('c' * 100));
    await finish(tester, container);
  });

  // FB03 B63: Enter in the name field saves like the Save button.
  testWidgets('Enter in the name field saves the category', (tester) async {
    final container = await pumpCategories(tester);

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Reading',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.byKey(const ValueKey('save-category')), findsNothing);
    expect(await categoryNames(tester, container), contains('Reading'));
    await finish(tester, container);
  });

  testWidgets('Enter on a blank name shows the same inline error', (
    tester,
  ) async {
    final container = await pumpCategories(tester);
    final before = await categoryNames(tester, container);

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('category-name')), '  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(nameFieldText('Enter a category name'), findsOneWidget);
    expect(await categoryNames(tester, container), before);
    await finish(tester, container);
  });

  testWidgets('a blank name shows an inline error instead of doing nothing', (
    tester,
  ) async {
    final container = await pumpCategories(tester);
    final before = await categoryNames(tester, container);

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('category-name')), '   ');
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    expect(find.text('New category'), findsOneWidget);
    expect(nameFieldText('Enter a category name'), findsOneWidget);
    expect(await categoryNames(tester, container), before);
    await finish(tester, container);
  });

  testWidgets('renaming to a blank name is rejected inline', (tester) async {
    final container = await pumpCategories(tester);
    await tester.tap(find.byKey(const ValueKey('edit-category-Work')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('category-name')), '');
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    expect(find.text('Edit category'), findsOneWidget);
    expect(nameFieldText('Enter a category name'), findsOneWidget);
    expect(await categoryNames(tester, container), contains('Work'));
    await finish(tester, container);
  });

  // UAT 2026-10-11 CAT-001: a new category must land after the existing ones,
  // not tie with the first one (sort_order 0).
  testWidgets('a new category is appended after the existing categories', (
    tester,
  ) async {
    final container = await pumpCategories(tester);
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Appended');
    await tester.tap(find.byKey(const ValueKey('save-category')));
    await settle(tester);

    final all = await runDb(
      tester,
      () => container.read(categoryRepositoryProvider).getAllCategories(),
    );
    expect(all.last.name, 'Appended');
    final maxOther = all
        .where((c) => c.name != 'Appended')
        .map((c) => c.sortOrder)
        .reduce((a, b) => a > b ? a : b);
    expect(all.last.sortOrder, greaterThan(maxOther));
    await finish(tester, container);
  });

  // UAT 2026-10-11 XC: the icon-only delete button needs an accessible name.
  testWidgets('delete button is named for assistive tech', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpCategories(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('delete-category-Work'))),
      isSemantics(tooltip: 'Delete category', isButton: true),
    );
    semantics.dispose();
    await finish(tester, container);
  });

  // UAT F-013: the FAB and the colour swatches are named for assistive tech.
  testWidgets('add FAB and colour swatches expose names and selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpCategories(tester);

    expect(
      tester.getSemantics(find.byKey(const ValueKey('add-category'))),
      isSemantics(tooltip: 'Add category', isButton: true),
    );

    await tester.tap(find.byKey(const ValueKey('add-category')));
    await settle(tester);
    for (final name in [
      'Purple',
      'Blue',
      'Green',
      'Red',
      'Yellow',
      'Pink',
      'Cyan',
      'Orange',
    ]) {
      expect(find.bySemanticsLabel('$name colour'), findsOneWidget);
    }
    // New categories default to the first colour.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Purple colour')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Blue colour')),
      isSemantics(isButton: true, isSelected: false),
    );
    final size = tester.getSize(find.byKey(const ValueKey('palette-0')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('palette-1')));
    await settle(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Blue colour')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Purple colour')),
      isSemantics(isSelected: false),
    );
    semantics.dispose();
    await finish(tester, container);
  });

  group('duplicate category name (F-012)', () {
    Future<int> workCount(WidgetTester tester, ProviderContainer container) =>
        runDb(
          tester,
          () async =>
              (await container
                      .read(categoryRepositoryProvider)
                      .getAllCategories())
                  .where((c) => c.name.trim().toLowerCase() == 'work')
                  .length,
        );

    Future<void> submitNewCategory(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('add-category')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('category-name')), name);
      await tester.tap(find.byKey(const ValueKey('save-category')));
      await settle(tester);
    }

    testWidgets('warns, and Create still saves the duplicate', (tester) async {
      final container = await pumpCategories(tester);
      // The seeded defaults include "Work"; case and spaces are ignored.
      expect(await workCount(tester, container), 1);

      await submitNewCategory(tester, '  work ');

      expect(
        find.text('A category named "work" already exists. Create anyway?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('duplicate-category-create')));
      await settle(tester);

      expect(await workCount(tester, container), 2);
      expect(find.text('New category'), findsNothing);
      await finish(tester, container);
    });

    testWidgets('Cancel aborts the create', (tester) async {
      final container = await pumpCategories(tester);

      await submitNewCategory(tester, 'Work');
      expect(find.textContaining('already exists'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('duplicate-category-cancel')));
      await settle(tester);

      expect(find.textContaining('already exists'), findsNothing);
      expect(await workCount(tester, container), 1);
      // The New category dialog stays open so the name can be changed.
      expect(find.text('New category'), findsOneWidget);
      await finish(tester, container);
    });

    testWidgets('a unique name saves without a warning', (tester) async {
      final container = await pumpCategories(tester);

      await submitNewCategory(tester, 'Workshop');

      expect(find.textContaining('already exists'), findsNothing);
      final names = await runDb(
        tester,
        () async =>
            (await container
                    .read(categoryRepositoryProvider)
                    .getAllCategories())
                .map((c) => c.name),
      );
      expect(names, contains('Workshop'));
      await finish(tester, container);
    });

    group('rename', () {
      Future<void> rename(WidgetTester tester, String to) async {
        await tester.tap(find.byKey(const ValueKey('edit-category-Health')));
        await settle(tester);
        await tester.enterText(find.byKey(const ValueKey('category-name')), to);
        await tester.tap(find.byKey(const ValueKey('save-category')));
        await settle(tester);
      }

      testWidgets('onto an existing name warns; Cancel keeps the form', (
        tester,
      ) async {
        final container = await pumpCategories(tester);

        await rename(tester, ' work ');

        expect(
          find.text('A category named "work" already exists. Rename anyway?'),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('duplicate-category-cancel')),
        );
        await settle(tester);
        expect(find.text('Edit category'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('category-name')))
              .controller!
              .text,
          ' work ',
        );
        expect(await workCount(tester, container), 1);

        await tester.tap(find.byKey(const ValueKey('save-category')));
        await settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('duplicate-category-create')),
        );
        await settle(tester);
        expect(await workCount(tester, container), 2);
        await finish(tester, container);
      });

      testWidgets('to its own name or only its case shows no warning', (
        tester,
      ) async {
        final container = await pumpCategories(tester);

        await rename(tester, 'Health');
        expect(find.textContaining('already exists'), findsNothing);
        expect(find.text('Edit category'), findsNothing);

        await rename(tester, 'HEALTH');
        expect(find.textContaining('already exists'), findsNothing);
        expect(find.text('Edit category'), findsNothing);
        await finish(tester, container);
      });
    });
  });
}
