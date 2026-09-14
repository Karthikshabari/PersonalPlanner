import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('first-launch guide reaches the planner', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: OnboardingScreen(onComplete: () => completed = true),
      ),
    );

    expect(find.text('Plan your day with confidence'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Start with a category'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Create your first task'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Use Inbox for unscheduled ideas'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    expect(completed, isTrue);
  });
}
