import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/theme/theme_mode_provider.dart';
import 'package:personal_planner/platform/desktop/keyboard_shortcuts.dart';
import 'package:personal_planner/platform/desktop/window_manager.dart';
import 'package:drift/native.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  group('Chunk 9 shortcut registry', () {
    test('generates bindings and help entries from one definition list', () {
      final definitions = PlannerShortcutRegistry.definitions;
      final activators = [
        for (final definition in definitions) ...definition.activators,
      ];

      expect(
        definitions.map((item) => item.action).toSet(),
        containsAll(PlannerShortcutAction.values),
      );
      expect(PlannerShortcutRegistry.bindings.length, activators.length);
      expect(activators.toSet(), hasLength(activators.length));
    });

    test('includes the complete movement, resize, and save shortcuts', () {
      final shortcuts = {
        for (final definition in PlannerShortcutRegistry.definitions)
          definition.action: definition.shortcut,
      };

      expect(shortcuts[PlannerShortcutAction.moveUp], 'Ctrl+↑');
      expect(shortcuts[PlannerShortcutAction.moveDown], 'Ctrl+↓');
      expect(shortcuts[PlannerShortcutAction.resizeUp], 'Shift+↑');
      expect(shortcuts[PlannerShortcutAction.resizeDown], 'Shift+↓');
      expect(shortcuts[PlannerShortcutAction.saveAndClose], 'Ctrl+Enter');
      expect(shortcuts[PlannerShortcutAction.help], '?');
    });
  });

  group('window bounds', () {
    final display = Display(
      id: 'primary',
      size: const Size(2560, 1440),
      visiblePosition: Offset.zero,
      visibleSize: const Size(1920, 1080),
      scaleFactor: 1,
    );

    test('clamps a removed-monitor rectangle to the available display', () {
      final result = clampWindowBounds(
        const Rect.fromLTWH(3000, 1500, 1000, 700),
        [display],
      );

      expect(result, const Rect.fromLTWH(920, 380, 1000, 700));
    });

    test('enforces the minimum size and keeps the result visible', () {
      final result = clampWindowBounds(
        const Rect.fromLTWH(-20, -30, 320, 240),
        [display],
      );

      expect(result.size, minimumPlannerWindowSize);
      expect(result.left, 0);
      expect(result.top, 0);
    });

    test('serializes and restores bounds without losing fractional values', () {
      const original = SavedWindowBounds(
        left: 12.5,
        top: 20.25,
        width: 1000.75,
        height: 700.5,
      );

      final restored = SavedWindowBounds.fromJson(original.toJson());
      expect(restored.rect, original.rect);
    });

    test(
      'fits a saved window on a work area smaller than the preferred minimum',
      () {
        final result = clampWindowBounds(const Rect.fromLTWH(0, 0, 900, 700), [
          Display(
            id: 'small',
            size: const Size(640, 480),
            visiblePosition: Offset.zero,
            visibleSize: const Size(640, 480),
            scaleFactor: 1,
          ),
        ]);

        expect(result, const Rect.fromLTWH(0, 0, 640, 480));
      },
    );
  });

  group('persisted theme mode', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      setupSqliteForTests();
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('defaults to dark and persists an explicit light choice', () async {
      expect(await container.read(themeModeProvider.future), ThemeMode.dark);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      final row =
          await (db.select(db.appSettings)
                ..where((setting) => setting.key.equals(themeModeSettingKey)))
              .getSingle();
      expect(row.value, 'light');
      expect(container.read(themeModeProvider), AsyncData(ThemeMode.light));
    });
  });

  test('question and shifted slash both activate the help intent', () {
    final help = PlannerShortcutRegistry.definitions.firstWhere(
      (definition) => definition.action == PlannerShortcutAction.help,
    );
    expect(
      help.activators,
      contains(const SingleActivator(LogicalKeyboardKey.question)),
    );
    expect(
      help.activators,
      contains(const SingleActivator(LogicalKeyboardKey.slash, shift: true)),
    );
  });
}
