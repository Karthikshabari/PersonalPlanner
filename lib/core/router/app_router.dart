import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/screens/categories_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/timeline/presentation/screens/day_view_screen.dart';
import '../widgets/adaptive_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/day',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveShell(child: child),
      routes: [
        GoRoute(
          path: '/day',
          builder: (context, state) => const DayViewScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesScreen(),
        ),
      ],
    ),
  ],
);
