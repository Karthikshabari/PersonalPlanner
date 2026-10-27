import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/screens/categories_screen.dart';
import '../../features/day_context/presentation/day_context_presets_screen.dart';
import '../../features/analytics/presentation/screens/analytics_screen.dart';
import '../../features/inbox/presentation/screens/inbox_screen.dart';
import '../../features/review/presentation/screens/daily_review_screen.dart';
import '../../features/review/presentation/screens/review_overview_screen.dart';
import '../../features/review/presentation/screens/weekly_review_screen.dart';
import '../../features/settings/presentation/screens/notifications_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/templates/presentation/screens/task_templates_screen.dart';
import '../../features/timeline/presentation/screens/day_view_screen.dart';
import '../../features/timeline/presentation/screens/week_view_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/sync/presentation/screens/sync_settings_screen.dart';
import '../search/page_search.dart';
import '../widgets/adaptive_shell.dart';

/// Navigator used by app-level actions that originate above the routed child.
final appNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: appNavigatorKey,
  initialLocation: '/day',
  // The Planner owns its deep links: Auth callbacks are consumed by the
  // raw-string callback router, and notifications navigate imperatively.
  // Without this, a platform-provided initial route (Android passes the
  // confirmation intent data to the engine) replaces '/day'; that URI has no
  // path, go_router normalizes it to '/', and no '/' route exists.
  overridePlatformDefaultLocation: true,
  errorBuilder: (context, state) {
    debugPrint('Router error: ${state.error}');
    return Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('We could not find that page.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/day'),
              child: const Text('Home'),
            ),
          ],
        ),
      ),
    );
  },
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveShell(child: child),
      routes: [
        GoRoute(
          path: '/day',
          builder: (context, state) => const DayViewScreen(),
        ),
        GoRoute(
          path: '/week',
          builder: (context, state) => const WeekViewScreen(),
        ),
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const PageSearchScope(
            hint: 'Search experiments',
            child: AnalyticsScreen(),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) =>
              SearchScreen(initialQuery: state.uri.queryParameters['q']),
        ),
        GoRoute(
          path: '/review/weekly',
          builder: (context, state) => const PageSearchScope(
            hint: 'Search weekly reviews',
            child: WeeklyReviewScreen(),
          ),
        ),
        GoRoute(
          path: '/review/overview',
          builder: (context, state) => ReviewOverviewScreen(
            initialWeekly: state.uri.queryParameters['tab'] == 'weekly',
          ),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) => const PageSearchScope(
            hint: 'Search daily reviews',
            child: DailyReviewScreen(),
          ),
        ),
        GoRoute(
          path: '/inbox',
          builder: (context, state) =>
              const PageSearchScope(hint: 'Search Inbox', child: InboxScreen()),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/settings/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/settings/day-contexts',
          builder: (context, state) => const DayContextPresetsScreen(),
        ),
        GoRoute(
          path: '/settings/sync',
          builder: (context, state) => const SyncSettingsScreen(),
        ),
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesScreen(),
        ),
        GoRoute(
          path: '/templates',
          builder: (context, state) => const TaskTemplatesScreen(),
        ),
      ],
    ),
  ],
);
