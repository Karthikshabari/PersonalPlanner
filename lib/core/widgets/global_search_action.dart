import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/adaptive_layout.dart';

/// The compact-shell entry point to the existing Search route.
///
/// Search remains in the desktop rail, so this action only renders where the
/// application uses bottom navigation.
class GlobalSearchAction extends StatelessWidget {
  const GlobalSearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
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
