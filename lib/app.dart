import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/widgets/error_panel.dart';
import 'platform/desktop/keyboard_shortcuts.dart';

class PersonalPlannerApp extends ConsumerWidget {
  const PersonalPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeModeProvider);
    if (themeAsync.hasError) {
      return MaterialApp(
        title: 'Personal Planner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ErrorPanel(
            message: friendlyErrorMessage(themeAsync.error!),
            onRetry: () => ref.invalidate(themeModeProvider),
          ),
        ),
      );
    }
    final themeMode = themeAsync.value ?? ThemeMode.dark;
    return MaterialApp.router(
      title: 'Personal Planner',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: appRouter,
      builder: (context, child) =>
          KeyboardShortcutHandler(child: child ?? const SizedBox.shrink()),
    );
  }
}
