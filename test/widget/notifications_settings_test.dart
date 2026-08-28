import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('reminder toggle and time persist to app_settings',
      (tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    // Settings → Notifications.
    await tester.tap(find.text('Settings').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('notifications-tile')));
    await settle(tester);

    expect(find.text('Notifications'), findsOneWidget);
    // Default: enabled at 21:00 (planner.md Chunk 6 #13).
    final switchFinder = find.byKey(const ValueKey('reminder-toggle'));
    final initialSwitch = tester.widget<SwitchListTile>(switchFinder);
    expect(initialSwitch.value, isTrue);
    expect(find.text('21:00'), findsOneWidget);

    // Disable → persisted.
    await tester.tap(switchFinder);
    await settle(tester);
    expect(
        await runDb(
            tester,
            () => container
                .read(appDatabaseProvider)
                .select(container.read(appDatabaseProvider).appSettings)
                .get()),
        containsSetting('review_reminder_enabled', 'false'));

    // Re-enable.
    await tester.tap(switchFinder);
    await settle(tester);

    // Change the time via the system time picker (text-input mode).
    await tester.tap(find.byKey(const ValueKey('reminder-time-tile')));
    await settle(tester);
    // Input mode; the dialog inherits PM from the 21:00 default.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await settle(tester);
    await tester.tap(find.text('AM'));
    await settle(tester);
    final fields = find.descendant(
        of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(fields.first, '08');
    await settle(tester);
    await tester.enterText(fields.last, '35');
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.text('08:35'), findsOneWidget);
    final rows = await runDb(
        tester,
        () => container
            .read(appDatabaseProvider)
            .select(container.read(appDatabaseProvider).appSettings)
            .get());
    expect(rows, containsSetting('review_reminder_time', '515'));

    // Screen reflects the stored state after a remount.
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await settle(tester);
    expect(find.text('08:35'), findsOneWidget);
    await finish(tester, container);
  });
}

Matcher containsSetting(String key, String value) =>
    predicate<List<dynamic>>(
      (rows) => rows.any((r) =>
          r.key == key && r.value == value),
      'contains app_settings row $key=$value',
    );
