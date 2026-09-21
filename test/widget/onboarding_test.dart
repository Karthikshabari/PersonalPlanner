import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('first launch opens the planner without the generic guide', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');

    await pumpApp(tester, container);

    expect(find.byType(DayViewScreen), findsOneWidget);
    expect(find.text('Plan your day with confidence'), findsNothing);
    expect(find.text('Skip guide'), findsNothing);
    await finish(tester, container);
  });

  testWidgets('legacy onboarding preference cannot block returning users', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .syncDao
          .setSetting('onboarding.completed', 'false'),
    );
    appRouter.go('/day');

    await pumpApp(tester, container);

    expect(find.byType(DayViewScreen), findsOneWidget);
    expect(find.text('Plan your day with confidence'), findsNothing);
    await finish(tester, container);
  });
}
