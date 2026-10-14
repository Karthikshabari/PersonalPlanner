import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/breakpoints.dart';
import '../layout/size_class_scope.dart';

/// The compact-shell entry point to the existing Search route.
///
/// Search is in the navigation rail from the medium size class up, so this
/// action only renders where the application uses bottom navigation.
class GlobalSearchAction extends StatelessWidget {
  const GlobalSearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DaySizeClass.of(context).isCompact) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const ValueKey('mobile-search-action'),
      tooltip: 'Search',
      icon: const Icon(Icons.search),
      onPressed: () => context.push('/search'),
    );
  }
}
