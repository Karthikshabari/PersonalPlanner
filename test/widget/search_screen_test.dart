import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/features/search/domain/search_result.dart';
import 'package:personal_planner/features/search/presentation/screens/search_screen.dart';
import 'package:personal_planner/features/search/providers/search_providers.dart';

SearchResult _result(int i, {String title = 'Task'}) => SearchResult(
  id: 'r$i',
  title: '$title $i',
  isInbox: false,
  startTime: DateTime(2026, 8, 24),
  status: TaskStatus.planned,
  categoryId: null,
  categoryColorHex: null,
  relevance: 0,
);

Future<void> _search(
  WidgetTester tester,
  List<SearchResult> results,
  String query,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [searchResultsProvider.overrideWith((ref, _) => results)],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.enterText(find.byKey(const ValueKey('search-input')), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('the first-100 note shows at 100 results and not at 99', (
    tester,
  ) async {
    await _search(tester, [for (var i = 0; i < 99; i++) _result(i)], 'task');
    expect(find.text('Showing the first 100'), findsNothing);
    expect(find.text('99 tasks'), findsOneWidget);

    await _search(tester, [for (var i = 0; i < 100; i++) _result(i)], 'tasks');
    expect(find.text('Showing the first 100'), findsOneWidget);
  });

  testWidgets('the title highlight ignores accents', (tester) async {
    await _search(tester, [_result(1, title: 'Café')], 'cafe');
    final text = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('search-result-r1')),
            matching: find.byType(RichText),
          )
          .first,
    );
    final marked = <String>[];
    text.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.fontWeight == FontWeight.w700) {
        marked.add(span.text!);
      }
      return true;
    });
    expect(marked, ['Café']);
  });
}
