import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../layout/adaptive_layout.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_tokens.dart';
import '../../features/review/providers/review_providers.dart';
import '../../features/timeline/presentation/providers/selected_date_provider.dart';
import '../utils/date_utils.dart';
import '../../features/settings/providers/week_start_provider.dart';
import '../../features/sync/domain/runtime_backend.dart';
import '../../features/sync/providers/runtime_backend_providers.dart';
import '../../features/sync/providers/sync_providers.dart';

typedef _Destination = (String, IconData, IconData, String);

class AdaptiveShell extends ConsumerWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  static const _desktopDestinations = [
    ('/day', Icons.calendar_today_outlined, Icons.calendar_today, 'Day'),
    ('/review', Icons.rate_review_outlined, Icons.rate_review, 'Review'),
    (
      '/analytics',
      Icons.bar_chart_outlined,
      Icons.bar_chart_rounded,
      'Insights',
    ),
    ('/search', Icons.search_outlined, Icons.search, 'Search'),
    ('/inbox', Icons.inbox_outlined, Icons.inbox, 'Inbox'),
    ('/categories', Icons.label_outline, Icons.label, 'Categories'),
    ('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  static const _mobileDestinations = [
    ('/day', Icons.calendar_today_outlined, Icons.calendar_today, 'Day'),
    ('/review', Icons.rate_review_outlined, Icons.rate_review, 'Review'),
    (
      '/analytics',
      Icons.bar_chart_outlined,
      Icons.bar_chart_rounded,
      'Insights',
    ),
    ('/inbox', Icons.inbox_outlined, Icons.inbox, 'Inbox'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Day selection following midnight while the app is open.
    ref.watch(selectedDateRolloverProvider);
    // Loads the week-start setting before any week screen reads it.
    ref.watch(weekStartDayProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = isDesktopWidth(constraints.maxWidth);
        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _buildRail(context),
                const VerticalDivider(width: 1),
                Expanded(child: _withBanner(child)),
              ],
            ),
          );
        }
        return Scaffold(
          body: _withBanner(child),
          bottomNavigationBar: _buildBottomBar(context),
        );
      },
    );
  }

  Widget _withBanner(Widget content) => Column(
    children: [
      const SignedOutBanner(),
      Expanded(child: content),
    ],
  );

  int? _selectedIndex(BuildContext context, List<_Destination> destinations) {
    final location = GoRouterState.of(context).uri.path;
    // Week is a Planner sub-view, so both shells keep Day selected while the
    // existing Day/Week switcher controls the actual routed view.
    if (location.startsWith('/week')) {
      return destinations.indexWhere((destination) => destination.$1 == '/day');
    }
    for (var i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].$1)) return i;
    }
    return null;
  }

  Widget _buildRail(BuildContext context) {
    final destinations = _desktopDestinations;
    final index = _selectedIndex(context, destinations) ?? 0;
    final tokens = AppThemeTokens.of(context);
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: (i) => _navigate(context, destinations[i].$1),
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.lg,
        ),
        child: IconButton(
          key: const ValueKey('home-navigation-shortcut'),
          tooltip: 'Home',
          icon: SizedBox.square(
            dimension: 24,
            child: Image.asset(
              'assets/branding/app_logo.png',
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          onPressed: () => _navigate(context, '/day'),
        ),
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          'PLAN',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: tokens.textMuted, letterSpacing: 1.6),
        ),
      ),
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
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index,
        onDestinationSelected: (i) => _navigate(context, destinations[i].$1),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.$2),
              selectedIcon: Icon(d.$3),
              label: d.$4,
            ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, String location) {
    final container = ProviderScope.containerOf(context, listen: false);
    final selectedDate = container.read(selectedDateProvider);
    if (location == '/week') {
      container.read(selectedWeekStartProvider.notifier).state = startOfWeek(
        selectedDate,
      );
    } else if (location == '/review') {
      container.read(selectedReviewDateProvider.notifier).state = selectedDate;
      container.read(selectedWeekStartProvider.notifier).state = startOfWeek(
        selectedDate,
      );
    } else if (location == '/day') {
      final current = GoRouterState.of(context).uri.path;
      if (current.startsWith('/review')) {
        container.read(selectedDateProvider.notifier).state = container.read(
          selectedReviewDateProvider,
        );
      }
    }
    context.go(location);
  }
}

/// Slim notice shown while a cloud backend is configured but nobody is signed
/// in, so the empty local-only data is not mistaken for lost data.
class SignedOutBanner extends ConsumerWidget {
  const SignedOutBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(runtimeBackendProvider);
    final session = ref.watch(authSessionProvider);
    if (backend is LocalOnlyRuntimeBackend ||
        !session.hasValue ||
        session.requireValue != null) {
      return const SizedBox.shrink();
    }
    final tokens = AppThemeTokens.of(context);
    return Material(
      color: tokens.pending.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 16),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Text('Signed out. You are seeing local-only data.'),
            ),
            TextButton(
              key: const ValueKey('signed-out-banner-sign-in'),
              onPressed: () => context.go('/settings/sync'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
