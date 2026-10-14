import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../layout/breakpoints.dart';
import '../layout/size_class_scope.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_tokens.dart';
import '../../features/review/providers/review_providers.dart';
import '../../features/timeline/presentation/widgets/day_layout.dart';
import '../../features/timeline/presentation/providers/selected_date_provider.dart';
import '../utils/date_utils.dart';
import '../../features/settings/providers/week_start_provider.dart';
import '../../features/sync/domain/runtime_backend.dart';
import '../../features/sync/providers/runtime_backend_providers.dart';
import '../../features/sync/providers/sync_providers.dart';

typedef _Destination = ({
  String path,
  IconData icon,
  IconData selectedIcon,
  String label,
});

const _primaryDestinations = <_Destination>[
  (
    path: '/day',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
    label: 'Day',
  ),
  (
    path: '/inbox',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox,
    label: 'Inbox',
  ),
  (
    path: '/review',
    icon: Icons.rate_review_outlined,
    selectedIcon: Icons.rate_review,
    label: 'Review',
  ),
  (
    path: '/analytics',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart_rounded,
    label: 'Insights',
  ),
];

const _secondaryDestinations = <_Destination>[
  (
    path: '/search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: 'Search',
  ),
  (
    path: '/categories',
    icon: Icons.label_outline,
    selectedIcon: Icons.label,
    label: 'Categories',
  ),
  (
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
];

const _moreIcon = Icons.more_horiz;

/// Routes the "More" entry stands for. Search is the compact top-bar action,
/// so the compact sheet lists only Categories and Settings.
const _morePaths = ['/search', '/categories', '/settings', '/templates'];

class AdaptiveShell extends ConsumerWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Day selection following midnight while the app is open.
    ref.watch(selectedDateRolloverProvider);
    // Loads the week-start setting before any week screen reads it.
    ref.watch(weekStartDayProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = Breakpoints.of(constraints.maxWidth);
        // The routed child is go_router's globally keyed shell Navigator, so
        // Day keeps its State when the body moves between the Scaffold body
        // and the rail's Row (guarded by shell_size_class_test.dart).
        final body = _withBanner(child);
        return DaySizeClass(
          sizeClass: sizeClass,
          child: sizeClass.hasRail
              ? Scaffold(
                  body: Row(
                    children: [
                      _buildRail(context, extended: sizeClass.railExtended),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  ),
                )
              : Scaffold(
                  body: body,
                  bottomNavigationBar: _buildBottomBar(context),
                ),
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

  /// Index into [_primaryDestinations] for the current route, or null for a
  /// secondary or unknown route.
  int? _primaryIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    // Week is a Planner sub-view, so both shells keep Day selected while the
    // existing Day/Week switcher controls the actual routed view.
    if (location.startsWith('/week')) return 0;
    for (var i = 0; i < _primaryDestinations.length; i++) {
      if (location.startsWith(_primaryDestinations[i].path)) return i;
    }
    return null;
  }

  bool _isMoreRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return _morePaths.any(location.startsWith);
  }

  Widget _buildRail(BuildContext context, {required bool extended}) {
    final index = _primaryIndex(context);
    final theme = Theme.of(context);
    final railTheme = NavigationRailTheme.of(context);
    // Built from the theme text styles: a bare TextStyle has no font family.
    final labelBase = theme.textTheme.labelMedium ?? theme.textTheme.bodySmall;
    final selectedStyle = labelBase
        ?.merge(railTheme.selectedLabelTextStyle)
        .copyWith(fontSize: 12);
    final unselectedStyle = labelBase
        ?.merge(railTheme.unselectedLabelTextStyle)
        .copyWith(fontSize: 12);
    final selected = _isMoreRoute(context);
    final location = GoRouterState.of(context).uri.path;
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = constraints.maxHeight < DayLayout.railCollapseHeight;
        return NavigationRail(
          selectedIndex: index,
          onDestinationSelected: (i) =>
              _navigate(context, _primaryDestinations[i].path),
          labelType: NavigationRailLabelType.none,
          extended: extended,
          scrollable: true,
          trailingAtBottom: !collapsed,
          selectedLabelTextStyle: selectedStyle,
          unselectedLabelTextStyle: unselectedStyle,
          leading: Padding(
            padding: EdgeInsets.only(
              top: collapsed ? AppSpacing.xs : AppSpacing.md,
              bottom: collapsed ? AppSpacing.sm : AppSpacing.lg,
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
          trailing: collapsed
              ? _RailMenu(
                  extended: extended,
                  selected: selected,
                  textStyle: selected ? selectedStyle : unselectedStyle,
                  onSelected: (path) => _navigate(context, path),
                  destinations: _secondaryDestinations,
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: extended ? _railItemWidth : _railIconWidth,
                        child: const Divider(height: AppSpacing.md),
                      ),
                      for (final d in _secondaryDestinations)
                        _RailItem(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: d.label,
                          extended: extended,
                          selected: location.startsWith(d.path),
                          textStyle: location.startsWith(d.path)
                              ? selectedStyle
                              : unselectedStyle,
                          onPressed: () => _navigate(context, d.path),
                        ),
                    ],
                  ),
                ),
          destinations: [
            for (final d in _primaryDestinations)
              NavigationRailDestination(
                // A rail with hidden labels has no tooltips of its own.
                icon: extended
                    ? Icon(d.icon)
                    : Tooltip(message: d.label, child: Icon(d.icon)),
                selectedIcon: extended
                    ? Icon(d.selectedIcon)
                    : Tooltip(message: d.label, child: Icon(d.selectedIcon)),
                label: Text(d.label),
              ),
          ],
        );
      },
    );
  }

  Widget? _buildBottomBar(BuildContext context) {
    // Secondary routes (Search, Categories, Settings, Templates) hide the bar.
    final index = _primaryIndex(context);
    if (index == null) return null;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (i == _primaryDestinations.length) {
            _showMoreSheet(context);
          } else {
            _navigate(context, _primaryDestinations[i].path);
          }
        },
        destinations: [
          for (final d in _primaryDestinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
          const NavigationDestination(icon: Icon(_moreIcon), label: 'More'),
        ],
      ),
    );
  }

  Future<void> _showMoreSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in _secondaryDestinations.skip(1))
            ListTile(
              key: ValueKey('more-sheet-${d.label.toLowerCase()}'),
              minTileHeight: 48,
              leading: Icon(d.icon),
              title: Text(d.label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // push, so Back returns to the screen the sheet opened from.
                context.push(d.path);
              },
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

const double _railIconWidth = 56;

/// Width of an extended rail item row (the theme's minExtendedWidth less the
/// divider inset).
const double _railItemWidth = 192;

/// A rail-styled button for the destinations that sit below the rail's own
/// group (Search, Categories, Settings, More). It mirrors the destination
/// look: a stadium indicator around the icon when selected, a tooltip when
/// labels are hidden, and the label beside the icon when extended.
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.extended,
    required this.selected,
    required this.textStyle,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool extended;
  final bool selected;
  final TextStyle? textStyle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final railTheme = NavigationRailTheme.of(context);
    final shape = railTheme.indicatorShape ?? const StadiumBorder();
    final iconTheme = selected
        ? railTheme.selectedIconTheme
        : railTheme.unselectedIconTheme;
    final pill = DecoratedBox(
      decoration: ShapeDecoration(
        color: selected ? railTheme.indicatorColor : null,
        shape: shape,
      ),
      child: SizedBox(
        width: _railIconWidth,
        height: 32,
        child: Icon(
          selected ? selectedIcon : icon,
          color: iconTheme?.color,
          size: 24,
        ),
      ),
    );
    final button = Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: SizedBox(
          height: 48,
          width: extended ? _railItemWidth : _railIconWidth,
          child: extended
              // Same geometry as the rail's own extended destinations: the
              // icon pill, then the label.
              ? Row(
                  children: [
                    // The row is centred in the 208 wide rail, 8 in from the
                    // edge; 4 more puts the pill where the rail's own is.
                    const SizedBox(width: AppSpacing.xs),
                    Center(child: pill),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                  ],
                )
              : Center(child: pill),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: extended ? button : Tooltip(message: label, child: button),
    );
  }
}

/// The rail's "More" entry for windows too short for the whole rail: it opens
/// a menu next to the rail with the secondary destinations.
class _RailMenu extends StatelessWidget {
  const _RailMenu({
    required this.extended,
    required this.selected,
    required this.textStyle,
    required this.onSelected,
    required this.destinations,
  });

  final bool extended;
  final bool selected;
  final TextStyle? textStyle;
  final ValueChanged<String> onSelected;
  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      key: const ValueKey('rail-more-menu'),
      alignmentOffset: Offset(
        (extended ? _railItemWidth : _railIconWidth) + AppSpacing.sm,
        -56,
      ),
      menuChildren: [
        for (final d in destinations)
          MenuItemButton(
            leadingIcon: Icon(d.icon),
            onPressed: () => onSelected(d.path),
            child: Text(d.label),
          ),
      ],
      builder: (context, controller, _) => _RailItem(
        icon: _moreIcon,
        selectedIcon: _moreIcon,
        label: 'More',
        extended: extended,
        selected: selected,
        textStyle: textStyle,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
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
