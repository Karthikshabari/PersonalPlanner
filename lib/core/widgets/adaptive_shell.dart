import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';

class AdaptiveShell extends StatelessWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  static const _destinations = [
    ('/day', Icons.calendar_today_outlined, Icons.calendar_today, 'Day'),
    ('/review', Icons.rate_review_outlined, Icons.rate_review, 'Review'),
    (
      '/inbox',
      Icons.inbox_outlined,
      Icons.inbox,
      'Inbox'
    ),
    (
      '/categories',
      Icons.label_outline,
      Icons.label,
      'Categories'
    ),
    (
      '/settings',
      Icons.settings_outlined,
      Icons.settings,
      'Settings'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            constraints.maxWidth >= AppConstants.desktopBreakpoint;
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

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].$1)) return i;
    }
    return 0;
  }

  Widget _buildRail(BuildContext context) {
    final index = _selectedIndex(context);
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: (i) => context.go(_destinations[i].$1),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: Icon(d.$2),
            selectedIcon: Icon(d.$3),
            label: Text(d.$4),
          ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final index = _selectedIndex(context);
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => context.go(_destinations[i].$1),
      destinations: [
        for (final d in _destinations)
          NavigationDestination(
            icon: Icon(d.$2),
            selectedIcon: Icon(d.$3),
            label: d.$4,
          ),
      ],
    );
  }
}
