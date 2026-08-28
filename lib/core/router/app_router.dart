import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/screens/categories_screen.dart';
import '../../features/inbox/presentation/screens/inbox_screen.dart';
import '../../features/review/presentation/screens/daily_review_screen.dart';
import '../../features/review/presentation/screens/weekly_review_screen.dart';
import '../../features/settings/presentation/screens/notifications_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/tags_screen.dart';
import '../../features/templates/presentation/screens/task_templates_screen.dart';
import '../../features/timeline/presentation/screens/day_view_screen.dart';
import '../../features/timeline/presentation/screens/week_view_screen.dart';
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
          path: '/week',
          builder: (context, state) => const WeekViewScreen(),
        ),
        GoRoute(
          path: '/review/weekly',
          builder: (context, state) => const WeeklyReviewScreen(),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) => const DailyReviewScreen(),
        ),
        GoRoute(
          path: '/inbox',
          builder: (context, state) => const InboxScreen(),
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
          path: '/settings/tags',
          builder: (context, state) => const TagsScreen(),
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
