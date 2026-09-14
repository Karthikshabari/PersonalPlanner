import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/schedule_fields.dart';

void main() {
  testWidgets('renders explicit date and time controls for both endpoints', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 9, 11, 23, 30);
    final end = DateTime.utc(2026, 9, 12, 0, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleFields(
            start: start,
            end: end,
            onStartChanged: (_) {},
            onEndChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('schedule-start-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-start-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-end-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-end-time')), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  testWidgets('shows equal/reversed interval validation without writing', (
    tester,
  ) async {
    final instant = DateTime.utc(2026, 9, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleFields(
            start: instant,
            end: instant,
            onStartChanged: (_) {},
            onEndChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('schedule-fields-error')), findsOneWidget);
    expect(find.text('End must be later than start'), findsOneWidget);
  });
}
