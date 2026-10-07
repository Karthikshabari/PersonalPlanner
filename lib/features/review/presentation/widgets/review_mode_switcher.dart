import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/adaptive_layout.dart';

/// Text-labelled mode switch kept at the top of both Review modes so Weekly
/// Review is discoverable without adding another navigation destination.
class ReviewModeSwitcher extends StatelessWidget {
  final bool weekly;
  final bool overview;
  final ValueChanged<String> onChanged;

  const ReviewModeSwitcher({
    super.key,
    required this.weekly,
    this.overview = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      key: const ValueKey('review-mode-switcher'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'daily', label: Text('Daily')),
        ButtonSegment(value: 'weekly', label: Text('Weekly')),
        ButtonSegment(value: 'overview', label: Text('Overview')),
      ],
      selected: {
        overview
            ? 'overview'
            : weekly
            ? 'weekly'
            : 'daily',
      },
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}

/// Opens a Review mode the same way Daily/Weekly already switch: replace on
/// desktop width, push on narrow layouts so Back returns.
void openReviewPath(BuildContext context, String path) {
  if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
    context.go(path);
  } else {
    context.push(path);
  }
}
