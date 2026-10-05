import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

/// UAT F-014: the sync-status icon must not stack Sync pages.
void main() {
  testWidgets('sync icon on the Sync page does not push another copy', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/inbox');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(appRouter.state.uri.path, '/inbox');

    // From another screen the icon still opens Sync settings.
    await tester.tap(find.byKey(const ValueKey('sync-status-action')));
    await settle(tester);
    expect(appRouter.state.uri.path, '/settings/sync');

    // On the Sync page itself, repeated taps are inert.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('sync-status-action')));
      await settle(tester);
    }
    expect(appRouter.state.uri.path, '/settings/sync');

    // One Back returns to where the user came from.
    appRouter.pop();
    await settle(tester);
    expect(appRouter.state.uri.path, '/inbox');
    await finish(tester, container);
  });
}
