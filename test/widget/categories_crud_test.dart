import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';

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

  testWidgets('create a category with name and palette color',
      (tester) async {
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
    final all =
        await runDb(tester, () => container.read(categoryRepositoryProvider).getAllCategories());
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
    await tester
        .tap(find.byTooltip('Focus category').first);
    await settle(tester);
    final work = await runDb(
      tester,
      () async => (await container.read(categoryRepositoryProvider).getAllCategories())
          .singleWhere((c) => c.name == 'Work'),
    );
    expect(work.isFocus, isTrue);
    await finish(tester, container);
  });

  testWidgets('delete asks for confirmation; tasks keep existing but lose the category', (tester) async {
    final container = await pumpCategories(tester);
    // Give Work a task first.
    final task = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).insertTask(Task(
            id: '',
            title: 'Categorized',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          )),
    );
    final work = await runDb(
      tester,
      () async => (await container.read(categoryRepositoryProvider).getAllCategories())
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
  });
}
