import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/timeline_overlap_action.dart';

void main() {
  testWidgets('dense overlap action opens titled task list and Open works', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 23, 9);
    final tasks = [
      for (var index = 0; index < 3; index++)
        Task(
          id: 'overlap-$index',
          title: 'Overlap $index',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          createdAt: start,
          updatedAt: start,
        ),
    ];
    final geometry = TimelineGeometry.layoutForDay(
      tasks: tasks,
      date: start,
    ).first;
    Task? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SizedBox(
          width: 70,
          height: 64,
          child: TimelineOverlapAction(
            geometry: geometry,
            tasks: tasks,
            date: start,
            onOpen: (task) => opened = task,
          ),
        ),
      ),
    );

    expect(find.text('3 overlapping tasks'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('timeline-overlap-action-overlap-0')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('3 overlapping tasks'), findsNWidgets(2));
    expect(find.textContaining('09:00'), findsWidgets);
    expect(find.text('Open'), findsNWidgets(3));

    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    expect(opened?.id, isNotNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
