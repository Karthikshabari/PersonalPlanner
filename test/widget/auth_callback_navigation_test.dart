import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/auth_callback.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';

import '../helpers/test_container.dart';

/// Confirmation-callback navigation handoff.
///
/// The hosted callback is delivered to the app by the OS intent and consumed by
/// the Planner's own raw-string callback router. The Flutter engine's automatic
/// deep-link bridge must therefore never turn that URI into a GoRouter location:
/// the callback URI has no path, GoRouter normalizes an empty path to `/`, and
/// this app has no `/` route, which produced the hosted "Page Not Found".
void main() {
  testWidgets(
    'cold start from the Auth callback link still lands on the day view',
    (tester) async {
      // Android passes the deep-link intent data as the engine's initial route,
      // which becomes PlatformDispatcher.defaultRouteName.
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '${AuthCallback.redirectUrl}?code=confirmation-code';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      final container = await buildTestContainer(tester);
      await pumpApp(tester, container);

      expect(
        find.text('Page Not Found'),
        findsNothing,
        reason:
            'GoRouter location: '
            '${appRouter.routerDelegate.currentConfiguration.uri}',
      );
      expect(find.textContaining('GoException'), findsNothing);
      // The existing canonical startup route, not the callback URI and not '/'.
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.path,
        '/day',
      );
      expect(find.byType(DayViewScreen), findsOneWidget);

      await teardownApp(tester, container);
    },
  );

  testWidgets('ordinary startup keeps using the canonical day route', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await pumpApp(tester, container);

    expect(find.text('Page Not Found'), findsNothing);
    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/day');
    expect(find.byType(DayViewScreen), findsOneWidget);

    await teardownApp(tester, container);
  });

  test('Android does not let the engine bridge deep links into Flutter routes', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    // app_links receives the confirmation intent directly, so the Planner's
    // callback router still gets the raw link; disabling the engine bridge only
    // stops the engine from pushing that URI at GoRouter.
    expect(
      RegExp(
        r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
        r'android:value="false"\s*/>',
      ).hasMatch(manifest),
      isTrue,
      reason: 'the engine deep-link bridge must stay disabled',
    );
  });
}
