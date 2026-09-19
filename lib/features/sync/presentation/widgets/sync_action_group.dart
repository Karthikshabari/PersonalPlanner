import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Responsive action row shared by the Sync surfaces.
///
/// The decision is made from the *available width*, never from the platform, so
/// a narrow Linux window behaves exactly like the phone layout and a wide
/// tablet gets the horizontal one. Below [stackBelow] the actions become
/// full-width and stacked, which keeps touch targets usable without squeezing
/// two buttons into a third of a phone screen.
class SyncActionGroup extends StatelessWidget {
  const SyncActionGroup({
    super.key,
    required this.actions,
    this.alignment = WrapAlignment.end,
    this.stackBelow = 420,
  });

  final List<Widget> actions;
  final WrapAlignment alignment;
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= stackBelow) {
          return Align(
            alignment: alignment == WrapAlignment.start
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: alignment,
              children: actions,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < actions.length; index += 1) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              actions[index],
            ],
          ],
        );
      },
    );
  }
}
