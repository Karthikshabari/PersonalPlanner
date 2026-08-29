import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/adaptive_layout.dart';

typedef _Destination = (String, IconData, IconData, String);

class AdaptiveShell extends StatelessWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  static const _desktopDestinations = [
    ('/day', Icons.calendar_today_outlined, Icons.calendar_today, 'Day'),
    ('/week', Icons.view_week_outlined, Icons.view_week, 'Week'),
    ('/review', Icons.rate_review_outlined, Icons.rate_review, 'Review'),
    ('/analytics', Icons.insights_outlined, Icons.insights, 'Analytics'),
    ('/search', Icons.search_outlined, Icons.search, 'Search'),
    ('/inbox', Icons.inbox_outlined, Icons.inbox, 'Inbox'),
    ('/categories', Icons.label_outline, Icons.label, 'Categories'),
    ('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  static const _mobileDestinations = [
    ('/day', Icons.calendar_today_outlined, Icons.calendar_today, 'Day'),
    ('/week', Icons.view_week_outlined, Icons.view_week, 'Week'),
    ('/inbox', Icons.inbox_outlined, Icons.inbox, 'Inbox'),
    ('/analytics', Icons.insights_outlined, Icons.insights, 'Analytics'),
    ('/search', Icons.search_outlined, Icons.search, 'Search'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = isDesktopWidth(constraints.maxWidth);
        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _buildRail(context),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }
        return Scaffold(
          body: child,
          bottomNavigationBar: _buildBottomBar(context),
        );
      },
    );
  }

  int? _selectedIndex(BuildContext context, List<_Destination> destinations) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].$1)) return i;
    }
    return null;
  }

  Widget _buildRail(BuildContext context) {
    final destinations = _desktopDestinations;
    final index = _selectedIndex(context, destinations) ?? 0;
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: (i) => context.go(destinations[i].$1),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.$2),
            selectedIcon: Icon(d.$3),
            label: Text(d.$4),
          ),
      ],
    );
  }

  Widget? _buildBottomBar(BuildContext context) {
    final destinations = _mobileDestinations;
    final index = _selectedIndex(context, destinations);
    if (index == null) return null;
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => context.go(destinations[i].$1),
      destinations: [
        for (final d in destinations)
          NavigationDestination(
            icon: Icon(d.$2),
            selectedIcon: Icon(d.$3),
            label: d.$4,
          ),
      ],
    );
  }
}
