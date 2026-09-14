import 'package:flutter/material.dart';

/// Text-labelled mode switch kept at the top of both Review modes so Weekly
/// Review is discoverable without adding another navigation destination.
class ReviewModeSwitcher extends StatelessWidget {
  final bool weekly;
  final ValueChanged<String> onChanged;

  const ReviewModeSwitcher({
    super.key,
    required this.weekly,
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
      ],
      selected: {weekly ? 'weekly' : 'daily'},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}
