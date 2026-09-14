import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/widgets/task_progress_background.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';

TimelineTaskGeometry geometry({int? actualMinutes}) {
  final start = DateTime.utc(2026, 7, 23, 9);
  final end = DateTime.utc(2026, 7, 23, 10);
  final task = Task(
    id: 'progress',
    title: 'Progress',
    startTime: start,
    endTime: end,
    actualDurationMin: actualMinutes,
    createdAt: start,
    updatedAt: start,
  );
  return TimelineGeometry.layoutForDay(tasks: [task], date: start).single;
}

void main() {
  testWidgets('planned and actual progress background paints in light theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SizedBox(
          width: 120,
          height: 64,
          child: TaskProgressBackground(geometry: geometry(actualMinutes: 45)),
        ),
      ),
    );

    expect(find.byType(TaskProgressBackground), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TaskProgressBackground),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('overtime progress background paints in dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SizedBox(
          width: 120,
          height: 64,
          child: TaskProgressBackground(geometry: geometry(actualMinutes: 75)),
        ),
      ),
    );

    expect(find.byType(TaskProgressBackground), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TaskProgressBackground),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
